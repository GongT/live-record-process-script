#!/usr/bin/env bash

set -Eeuo pipefail

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source ../lib/inc.sh

LAST_TITLE=""
FILE_ARR=()
function commit() {
	local FIRST_FILE FIRST_TIME I SRC_FILE WORKSPACE_DIR DATES TITLE
	FIRST_FILE="${FILE_ARR[0]}"
	FIRST_TIME=$(read_time_from_video "$FIRST_FILE")
	# echo "FIRST_TIME=$FIRST_TIME   LAST_TITLE=$LAST_TITLE"

	WORKSPACE_DIR=$(dirname "$FIRST_FILE")

	DATES=$(date "--date=@$FIRST_TIME" '+%Y%m%d')
	TITLE=$(escape_filename "$LAST_TITLE")
	SRC_FILE="$WORKSPACE_DIR/$DATES $TITLE.options"

	local OPEN_TIME='00:00' ENABLED='1' LOCKED='0'
	if [[ -e $SRC_FILE ]]; then
		eval "$(grep -E 'OPEN_TIME=|ENABLED=|LOCKED=' "$SRC_FILE")"
	fi

	if [[ $LOCKED == 0 ]]; then
		mkdir -p "$(dirname "$SRC_FILE")"
		{
			echo "OPEN_TIME=$OPEN_TIME"
			echo "ENABLED=$ENABLED"
			echo "LOCKED=$LOCKED"
			echo "PARTS=("
			for I in "${FILE_ARR[@]}"; do
				printf "\t%q\n" "$I"
			done
			echo ")"
		} >"$SRC_FILE"

		echo_info "写入文件: $SRC_FILE"
	fi

	LAST_TITLE=""
	FILE_ARR=()
}
function do_single() {
	local FNAME=$1 TITLE UTIME
	UTIME=$(read_time_from_video "$FNAME" || true)
	TITLE=$(read_title_from_video "$FNAME" || true)

	if [[ ! $UTIME ]] || [[ ! $TITLE ]]; then
		echo_error "文件没有时间或标题"
		return
	fi

	if [[ $LAST_TITLE != "$TITLE" ]] && [[ $LAST_TITLE ]]; then
		commit
	fi

	# echo "$FNAME --- $TITLE"
	LAST_TITLE="$TITLE"
	FILE_ARR+=("$FNAME")
}

cd records
mapfile -d '' FILES < <(find . \( -name '*.flv' -o -name '*.mp4' \) -print0 | sort --zero-terminated)

for I in "${FILES[@]}"; do
	do_single "$I"
done
