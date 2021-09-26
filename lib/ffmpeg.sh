#!/usr/bin/env bash

FF_ARGS=(
	-hide_banner
	-loglevel error
	-stats
	-threads $(($(nproc) * 2 / 3))
	-y
)
FF_OUTPUT_ARGS=(
	# copies all global metadata
	-map_metadata 0
	# copies video stream metadata
	-map_metadata:s:v 0:s:v
	# copies audio stream metadata
	-map_metadata:s:a 0:s:a
)

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
		"${FF_ARGS[@]}"
		-f concat -safe 0
		-i "$INPUT"
		-passlogfile "$PASS_LOG"
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
	if ! [[ -e "$CACHE_DIR/break-screen/$DIFF_TIME.mp4" ]]; then
		echo_debug "创建贴片视频 $DIFF_TIME"
		mkdir -p "$CACHE_DIR/break-screen"
		ffmpeg -hide_banner -loop 1 -framerate "60" -i "$SCRIPT_ROOT/break-screen.png" -c:v libx264 -t "$DIFF_TIME" -pix_fmt yuv420p "$CACHE_DIR/break-screen/$DIFF_TIME.mp4" -loglevel error -stats 1>&2
	fi
	echo "$CACHE_DIR/break-screen/$DIFF_TIME.mp4"
}

function get_video_time_seconds() {
	ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1"
}

function calc_diff() {
	local A=$1 B=$2 START_UTIME_A TIME_A START_UTIME_B DIFF_TIME
	START_UTIME_A=$(read_time_from_video "$A")
	TIME_A=$(get_video_time_seconds "$A")
	START_UTIME_B=$(read_time_from_video "$B")

	DIFF_TIME=$(float_add "$START_UTIME_B" "-$START_UTIME_A" "-$TIME_A")

	echo_debug "中断: $START_UTIME_B - $START_UTIME_A - $TIME_A = $DIFF_TIME"
	if [[ ${DIFF_TIME%.*} -gt 5 ]]; then
		DIFF_TIME=5
	fi
	if [[ ${DIFF_TIME%.*} -lt 0 ]]; then
		die "中断小于0"
	fi

	echo "$DIFF_TIME"
}

function ffmpeg_copy_streams() {
	local OPEN_TIME=$1 INPUT=$2 OUTPUT=$3
	mkdir -p "$(dirname "$OUTPUT")"
	x ffmpeg "${FF_ARGS[@]}" -i "$INPUT" -ss "$OPEN_TIME" -c copy "${FF_OUTPUT_ARGS[@]}" "$OUTPUT"
}

function encode_twopass() {
	local DIST="$1" TMPFILE="$2" VIDEO_BITRATE="$3" AUDIO_BITRATE="$4"

	local DIST_REL DIST_BASE PASSLOG_FILE PASSLOG_OK_FILE
	DIST_REL=${DIST#"$ROOT/"}
	DIST_BASE=$(basename "$DIST_REL" .mp4)
	PASSLOG_FILE="$CACHE_DIR/PASSLOGS/$DIST_BASE/stat"
	PASSLOG_OK_FILE="$CACHE_DIR/PASSLOGS/$DIST_BASE/complete.ok"

	local INPUT_ARGS AUDIO_ARGS VIDEO_ARGS
	build_args "$TMPFILE" "$VIDEO_BITRATE" "$AUDIO_BITRATE" "$PASSLOG_FILE"

	if ! [[ -e $PASSLOG_OK_FILE ]]; then
		echo_info "第一次编码"
		mkdir -p "$(dirname "$PASSLOG_FILE")"
		x ffmpeg \
			"${INPUT_ARGS[@]}" \
			"${AUDIO_ARGS[@]}" \
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
		"${FF_OUTPUT_ARGS[@]}" \
		"$DIST"
}

function concat_compress_files() {
	local OPEN_TIME="$1" DIST="$2" DIFF_TIME DIFF_FILE TMPFILE LAST FILE TIME_SECONDS=0
	shift
	shift

	TMPFILE=$(create_temp ffmpeg-parts-XXXXXXXX.txt)

	LAST=$1
	TIME_SECONDS=$(float_add "$TIME_SECONDS" "$(get_video_time_seconds "$LAST")")
	echo "file '$(realpath --canonicalize-existing "$LAST")'" | tee "$TMPFILE"
	shift

	for FILE; do
		DIFF_TIME=$(calc_diff "$LAST" "$FILE")
		DIFF_FILE=$(create_diff_file "$DIFF_TIME")

		echo "file '$DIFF_FILE'" | tee -a "$TMPFILE"
		echo "file '$(realpath --canonicalize-existing "$FILE")'" | tee -a "$TMPFILE"

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
		echo_debug "目标${DEBUG}比特率 [${BITRATE}] 超出要求，调整为 ${MAX_BR} $(human_readable_br "$MAX_BR")"
		BITRATE="$MAX_BR"
	else
		echo_debug "目标${DEBUG}比特率 ${BITRATE} $(human_readable_br "$BITRATE")"
	fi
	echo "${BITRATE%.*}"
}

function human_readable_br() {
	local BR=$1 OUT=''

	OUT+="("
	OUT+=$(echo "scale=2; $BR / 1024 / 1024" | bc)
	OUT+="mbps)"
	OUT+=" ("
	OUT+=$(echo "scale=2; $BR / 1024" | bc)
	OUT+="kbps)"

	echo "$OUT"
}
