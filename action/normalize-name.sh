#!/usr/bin/env bash

set -Eeuo pipefail

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source ../lib/inc.sh

mapfile -d '' FILES < <(find . \( -name '*.flv' -o -name '*.mp4' -o -name '*.xml' \) -print0)
for FNAME in "${FILES[@]}"; do
	EXTNAME=$(extname "$FNAME")
	TIME=$(read_time_from_file "$FNAME") || {
		echo_info "跳过文件（无法处理） - $FNAME"
		continue
	}
	TITLE=$(read_title_from_file "$FNAME") || {
		echo_info "跳过文件（无法处理） - $FNAME"
		continue
	}

	TITLE=$(escape_filename "$TITLE")

	FOLDER=$(date "--date=@$TIME" '+records/%Y-%m/%d')
	TIME_PREFIX=$(date "--date=@$TIME" '+[%Y%m%d-%H%M%S] ')
	DIST="$FOLDER/${TIME_PREFIX}$TITLE.$EXTNAME"

	if [[ $DIST == "$FNAME" ]]; then
		echo_debug "跳过文件（没有改变） - $FNAME"
		continue
	fi

	if [[ -e $DIST ]]; then
		if [[ "$(realpath -m "$FNAME")" != "$(realpath -m "$DIST")" ]]; then
			echo_error "目标文件存在: $FNAME => $DIST"
			mkdir -p duplicate
			DIST="duplicate/${TIME_PREFIX}$TITLE.$RANDOM.$EXTNAME"
			echo_info "移动重复文件: $FNAME -> $DIST"
			mv -n "$FNAME" "$DIST"
		else
			echo_debug "目标文件存在: $FNAME => $DIST"
		fi
	else
		mkdir -p "$FOLDER"
		echo_info "移动文件: $FNAME -> $DIST"
		mv -n "$FNAME" "$DIST"
	fi
done
