#!/usr/bin/env bash

set -Eeuo pipefail

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source ../lib/inc.sh

cd records
mapfile -d '' FILES < <(find . -name '*.options' -print0 | sort --zero-terminated)

for I in "${FILES[@]}"; do
	declare OPEN_TIME='00:00'
	declare -i ENABLED='1'
	declare -i LOCKED='0'
	declare -a PARTS=()
	declare OUTPUT=''

	# shellcheck source=/dev/null
	source "$I"

	if [[ $ENABLED == 0 ]] || [[ ${#PARTS[@]} -eq 0 ]]; then
		continue
	fi

	SINGLE_EXTNAME=$(extname "${PARTS[0]}")
	if [[ ! $OUTPUT ]]; then
		OUTPUT=$(read_title_from_file "${PARTS[0]}")
	fi
	UTIME=$(read_time_from_file "${PARTS[0]}")

	TITLE="$(date "--date=@$UTIME" '+%Y-%m-%d') $(escape_filename "$OUTPUT")"
	DIST_DIR="$ROOT/compress/$(date "--date=@$UTIME" '+%Y-%m')"
	if [[ -e "$DIST_DIR/${TITLE}.mp4" ]] || [[ -e "$DIST_DIR/${TITLE}.$SINGLE_EXTNAME" ]]; then
		continue
	fi

	echo_info "$TITLE"
	declare TOTAL_FILE_SIZE=0
	for FILE in "${PARTS[@]}"; do
		TOTAL_FILE_SIZE=$(float_add "$TOTAL_FILE_SIZE" "$(get_file_size "$FILE")")
	done
	echo "总文件大小: $TOTAL_FILE_SIZE"
	if [[ ${TOTAL_FILE_SIZE%.*} -le "${MAX_FILE_SIZE%.*}" ]]; then
		echo_success "文件大小符合要求"
		if [[ ${#PARTS[@]} -eq 1 ]]; then
			ensure_symlink "$DIST_DIR/${TITLE}.$SINGLE_EXTNAME" "${PARTS[0]}"
		else
			echo_success "简单连接文件"
			concat_files "$DIST_DIR/${TITLE}.mp4" "${PARTS[@]}"
			exit
		fi
	else
		echo_success "文件需要压缩"
		concat_compress_files "$DIST_DIR/${TITLE}.mp4" "${PARTS[@]}"
	fi

	echo_success "完成！"
	echo
	echo

	exit 233
done
