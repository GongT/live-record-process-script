#!/usr/bin/env bash

function build_args() {
	local INPUT=$1 VIDEO_BITRATE=$2 AUDIO_BITRATE=$3 PASS_LOG=$4

	local X264OPTS=(
		# 这些是从上传工具里复制出来的
		merange=24
		subme=10
		aq-mode=3
		aq-strength=0.8
		min-keyint=1
		keyint=300
		qpmin=13
		bframes=6
		b-adapt=2
		qcomp=0.7
		ratetol=inf
	)

	INPUT_ARGS=(
		-hide_banner -loglevel error -stats
		-f concat -safe 0
		-i "$INPUT"
		-threads $(($(nproc) / 2))
		-passlogfile "$PASS_LOG"
		-y
	)
	OUTPUT_ARGS=(
		# copies all global metadata
		-map_metadata 0
		# copies video stream metadata
		-map_metadata:s:v 0:s:v
		# copies audio stream metadata
		-map_metadata:s:a 0:s:a
	)
	AUDIO_ARGS=(
		### 音频编码选项
		-c:a aac
		-b:a "$AUDIO_BITRATE"
	)

	VIDEO_ARGS=(
		### 视频编码选项 https://trac.ffmpeg.org/wiki/Encode/H.264
		-c:v libx264

		-x264opts "$(
			IFS=:
			echo "${X264OPTS[*]}"
		)"

		-b:v "$VIDEO_BITRATE"

		# 目标帧率
		-r 30

		# 录像文件不需要缩放
		# -vf setdar=1.77778,scale=1920:1080
		# -sws_flags bicubic
		# 压缩预设
		-vsync vfr # cfr
		-preset veryfast
		# -profile:v main
		-level 4.0
		# 颜色格式（似乎是部分播放器有问题所以写明，实际没有作用）
		-pix_fmt yuv420p
		#
		# -filter_complex "[0:v]mpdecimate[out]"
	)
}

function get_video_time_seconds() {
	local INPUT="$1"
	ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT"
}

function create_diff_file() {
	local DIFF_TIME=$1
	if ! [[ -e "$SCRIPT_ROOT/.break-screen/$DIFF_TIME.mp4" ]]; then
		echo_success "创建贴片视频 $DIFF_TIME"
		mkdir -p "$SCRIPT_ROOT/.break-screen"
		ffmpeg -hide_banner -loop 1 -framerate "$FPS" -i "$SCRIPT_ROOT/break-screen.png" -c:v libx264 -t "$DIFF_TIME" -pix_fmt yuv420p "$SCRIPT_ROOT/.break-screen/$DIFF_TIME.mp4" -loglevel error -stats &>"$SCRIPT_ROOT/.break-screen/$TIME.log"
	fi
}

function get_video_time_seconds() {
	ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1"
}

function concat_files() {
	local DIST="$1" TMPFILE LAST FILE DIFF_TIME TIME_SECONDS
	shift

	TMPFILE=$(mktemp ffmpeg-parts-XXXXXXXX)

	LAST=$1
	echo "file '$(realpath --canonicalize-existing "$LAST")'" >"$TMPFILE"
	shift

	for FILE; do
		DIFF_TIME=$(calc_diff "$LAST" "$FILE")

		create_diff_file "$DIFF_TIME"

		echo "file '$SCRIPT_ROOT/.break-screen/$DIFF_TIME.mp4'" >"$TMPFILE"
		echo "file '$(realpath --canonicalize-existing "$LAST")'" >"$TMPFILE"

		LAST="$FILE"
	done
}

function encode_twopass() {
	local DIST="$1" TMPFILE="$2" VIDEO_BITRATE="$3" AUDIO_BITRATE="$4"

	local DIST_REL=${DIST#"$ROOT/"}
	local PASSLOG_FILE="$ROOT/PASSLOGS/$DIST_REL/stat"
	local PASSLOG_OK_FILE="$ROOT/PASSLOGS/$DIST_REL/complete.ok"

	local INPUT_ARGS OUTPUT_ARGS AUDIO_ARGS VIDEO_ARGS
	build_args "$TMPFILE" "$VIDEO_BITRATE" "$AUDIO_BITRATE" "$PASSLOG_FILE"

	if ! [[ -e $PASSLOG_OK_FILE ]]; then
		echo_info "第一次编码"
		mkdir -p "$(dirname "$PASSLOG_FILE")"
		x ffmpeg \
			"${INPUT_ARGS[@]}" \
			"${VIDEO_ARGS[@]}" \
			-an \
			-pass 1 \
			-f mp4 \
			/dev/null
		touch "$PASSLOG_OK_FILE"
	fi

	echo_info "第二次编码" "$OUTPUT"
	mkdir -p "$(dirname "$DIST")"
	x ffmpeg \
		"${INPUT_ARGS[@]}" \
		"${AUDIO_ARGS[@]}" \
		"${VIDEO_ARGS[@]}" \
		-pass 2 \
		"${OUTPUT_ARGS[@]}" \
		"$DIST"
}

function concat_compress_files() {
	local DIST="$1" DIFF_TIME DIFF_FILE TMPFILE LAST FILE TIME_SECONDS=0
	shift

	TMPFILE=$(mktemp ffmpeg-parts-XXXXXXXX.txt)

	LAST=$1
	TIME_SECONDS=$(float_add "$TIME_SECONDS" "$(get_video_time_seconds "$LAST")")
	echo "file '$(realpath --canonicalize-existing "$LAST")'" >"$TMPFILE"
	shift

	for FILE; do
		DIFF_TIME=$(calc_diff "$LAST" "$FILE")
		DIFF_FILE=$(create_diff_file "$DIFF_TIME")

		echo "file '$DIFF_FILE'" >"$TMPFILE"
		echo "file '$(realpath --canonicalize-existing "$FILE")'" >"$TMPFILE"

		TIME_SECONDS=$(float_add "$TIME_SECONDS" "$DIFF_TIME" "$(get_video_time_seconds "$FILE")")

		LAST="$FILE"
	done
	echo_info "时长:" "$TIME_SECONDS"

	local VIDEO_BITRATE AUDIO_BITRATE
	VIDEO_BITRATE=$(calc_bitrate '视频' "$TIME_SECONDS" "$MAX_VIDEO_SIZE" "$MAX_VIDEO_BITRATE")
	AUDIO_BITRATE=$(calc_bitrate '音频' "$TIME_SECONDS" "$MAX_AUDIO_SIZE" "$MAX_AUDIO_BITRATE")

	encode_twopass "$DIST" "$TMPFILE" "$VIDEO_BITRATE" "$AUDIO_BITRATE"
}

function calc_bitrate() {
	local DEBUG=$1 TIME=$2 MAX_SIZE=$3 MAX_BR=$4

	BITRATE=$(echo "scale=4; 8 * $MAX_SIZE / $TIME" | bc)

	if [[ ${BITRATE%.*} -gt ${MAX_BR%.*} ]]; then
		echo_debug "目标${DEBUG}比特率 [${BITRATE%.*}] 超出要求，调整为 ${MAX_BR%.*}"
		VIDEO_BITRATE="$MAX_BR"
	else
		echo_debug "目标${DEBUG}比特率 ${BITRATE%.*}"
	fi
	echo "${BITRATE%.*}"
}
