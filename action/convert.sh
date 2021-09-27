#!/usr/bin/env bash

set -Eeuo pipefail

env 

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source ../lib/inc.sh

function create_variables() {
	if [[ ! $OUTPUT ]]; then
		OUTPUT=$(read_title_from_file "$FIRST_FILE")
	fi
	local UTIME
	UTIME=$(read_time_from_file "$FIRST_FILE")

	TITLE="$(date "--date=@$UTIME" '+%Y-%m-%d') $(escape_filename "$OUTPUT")"
	echo_debug "$TITLE"

	unset OUTPUT

	DIST_DIR="$ROOT/compress/$(date "--date=@$UTIME" '+%Y-%m')"
	TEMP_OUTPUT="$TMPDIR/compress/${TITLE}.mp4"
	DIST="$DIST_DIR/${TITLE}.mp4"
}

function output_exists() {
	local SINGLE_EXTNAME
	SINGLE_EXTNAME=$(extname "$FIRST_FILE")
	if [[ -e "$DIST_DIR/${TITLE}.mp4" ]]; then
		echo_debug "目标存在: $DIST_DIR/${TITLE}.mp4"
		return
	fi
	if [[ -e "$DIST_DIR/${TITLE}.$SINGLE_EXTNAME" ]]; then
		echo_debug "目标(链接)存在: $DIST_DIR/${TITLE}.$SINGLE_EXTNAME"
		return
	fi

	return 1
}

function run_one() {
	local OPEN_TIME='00:00'
	local -i ENABLED='1'
	local -a PARTS=()
	local -a FILTERD_PARTS=()
	local OUTPUT=''

	# shellcheck source=/dev/null
	source "$I"

	if [[ $ENABLED == 0 ]] || [[ ${#PARTS[@]} -eq 0 ]]; then
		echo_debug "无输入\n\n"
		return
	fi

	local FILTERD_PARTS=("${PARTS[@]}")
	local FIRST_FILE="${FILTERD_PARTS[0]}"

	local TITLE='' DIST_DIR='' DIST='' TEMP_OUTPUT=''
	create_variables

	if output_exists; then
		return
	fi

	if [[ ${#FILTERD_PARTS[@]} -eq 1 ]]; then
		local FILE_SIZE
		FILE_SIZE="$(get_file_size "$FIRST_FILE")"
		echo_debug " * $(basename "$FIRST_FILE") = $FILE_SIZE ($((FILE_SIZE / 1024 / 1024))M / $((FILE_SIZE / 1024 / 1024 / 1024))G)"
		if [[ ${FILE_SIZE%.*} -le ${MAX_FILE_SIZE%.*} ]]; then
			echo_success "单文件模式"

			if [[ $OPEN_TIME == '00:00' ]]; then
				echo_success "链接目标"
				ensure_symlink "$DIST" "$FIRST_FILE"
			else
				echo_success "剪切文件: $OPEN_TIME"
				ffmpeg_copy_streams "$OPEN_TIME" "$FIRST_FILE" "$DIST"
			fi
			return
		else
			echo_debug "单文件 | 过大"
		fi
	else
		echo_debug "多文件"
	fi

	concat_compress_files "$OPEN_TIME" "$TEMP_OUTPUT" "${FILTERD_PARTS[@]}"

	if [[ $OPEN_TIME != '00:00' ]]; then
		echo_success "剪切文件: $OPEN_TIME"
		ffmpeg_copy_streams "$OPEN_TIME" "$TEMP_OUTPUT" "$DIST"
		echo_error rm -f "$TEMP_OUTPUT"
	else
		echo_debug "移动结果文件"
		mkdir -p "$(dirname "$DIST")"
		mv "$TEMP_OUTPUT" "$DIST"
	fi
}

export SCOPE="${1:-.}"
cd records
mapfile -d '' FILES < <(find "$SCOPE" -name '*.options' -print0 | sort --zero-terminated)

for I in "${FILES[@]}"; do
	echo -e "\e[38;5;12;7m$I\e[0m" >&2

	run_one "$I"

	echo -e "\e[38;5;10;7m完成\e[0m" >&2
	echo
	echo
done
