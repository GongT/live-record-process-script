#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_ROOT="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"

cd "$SCRIPT_ROOT/lib"
source output.sh
source ffmpeg.sh
source ../config.sh

set -a
# shellcheck source=../.env
source "$SCRIPT_ROOT/.env"
set +a

if [[ ! ${CACHE_DIR:-} ]]; then
	if [[ "${SYSTEM_COMMON_CACHE:-}" ]]; then
		declare -rx CACHE_DIR="$SYSTEM_COMMON_CACHE/live-encoding"
	elif [[ ${STATE_DIRECTORY:-} ]]; then
		declare -rx CACHE_DIR="$STATE_DIRECTORY"
	else
		declare -rx CACHE_DIR="$TMPDIR/cache"
	fi
fi
echo_debug "CACHE_DIR=$CACHE_DIR"

if [[ ! ${TMPDIR:-} ]]; then
	if [[ "${RUNTIME_DIRECTORY:-}" ]]; then
		export TMPDIR="$RUNTIME_DIRECTORY"
	else
		export TMPDIR="$CACHE_DIR/TEMP"
	fi
fi
echo_debug "TMPDIR=$TMPDIR"

mkdir -p "$TMPDIR"

if [[ ! ${LIVE_ROOT:-} ]] || [[ ! ${ROOM:-} ]]; then
	die "缺少环境变量 [ $SCRIPT_ROOT/.env ]: LIVE_ROOT ROOM "
fi

_ROOT_DIR=$(realpath -e "$LIVE_ROOT/$ROOM") || die "录像目录不存在"
cd "$_ROOT_DIR"
declare -r ROOT="$_ROOT_DIR"

function x() {
	echo_debug " + $*"
	nice -n 19 "$@"
}
function read_time_from_danmaku() {
	local F=$1 start_time='' TIMES
	TIMES=$(cat "$F" | grep 'BililiveRecorderRecordInfo' | grep -o 'start_time=".*"') \
		|| error "无法从文件 $F 中获取时间"
	eval "$TIMES"

	date "--date=$start_time" +%s || error "文件 $F 中的时间格式无法解析: $start_time"
}

function read_time_from_video_metadata() {
	local SOURCE_FILE="$1" MEDIA_START_TIME
	MEDIA_START_TIME=$(mediainfo --Output=JSON "$SOURCE_FILE" | jq -r '.media.track[].extra.StartTime| select(.)')

	if ! [[ "$MEDIA_START_TIME" ]]; then
		# echo_debug "视频标签中没有启动时间: $SOURCE_FILE"
		return 1
	fi

	date "--date=$MEDIA_START_TIME" +%s || error "文件 $SOURCE_FILE 中的时间格式无法解析: $MEDIA_START_TIME"
}

function read_time_from_video() {
	local SOURCE_FILE="$1" BASE_NAME S SDATE STIME

	if read_time_from_video_metadata "$SOURCE_FILE"; then
		return
	fi
	# echo_debug "视频标签中没有启动时间: $SOURCE_FILE"

	BASE_NAME=$(basename "$SOURCE_FILE")
	if [[ $BASE_NAME == '['*']'* ]]; then
		S=$(echo "$BASE_NAME" | grep -oP '^\[.*?\]')
		S=${S:1:-1}
		SDATE=${S%% *}
		STIME=${S##* }
		if [[ $SDATE == "$STIME" ]]; then
			STIME=''
		else
			STIME=${STIME//-/:}
		fi

		if date "--date=$SDATE $STIME" +%s 2>/dev/null; then
			return
		fi

		if echo "$SDATE" | grep -qP '^[0-9]{8}'; then
			SDATE=$(echo "$SDATE" | grep -oP '^[0-9]{8}')
			local Y M D
			Y="${SDATE:0:4}"
			M="${SDATE:4:2}"
			D="${SDATE:6:2}"

			if date "--date=$M/$D/$Y" +%s 2>/dev/null; then
				return
			fi
		fi

		error "文件名称 $SOURCE_FILE 的时间格式无法解析: $SDATE $STIME"
	fi

	error "文件中找不到任何时间 $BASE_NAME"
}

function read_title_from_danmaku() {
	local F=$1 title='' TITLES
	TITLES=$(cat "$F" | grep 'BililiveRecorderRecordInfo' | grep -o 'title=".*"') \
		|| error "无法从文件 $F 中获取标题"
	eval "$TITLES"

	if ! [[ "$title" ]]; then
		error "无法从文件 $F 中获取标题"
	fi
	echo "$title"
}

function read_title_from_video() {
	local SOURCE_FILE=$1 BASE_NAME TITLE
	TITLE=$(mediainfo --Output=JSON "$SOURCE_FILE" | jq -r '.media.track[].Title | select(.)')
	if [[ $TITLE ]]; then
		echo "$TITLE"
		return
	fi

	BASE_NAME=$(basename "$SOURCE_FILE" .flv)
	BASE_NAME=$(basename "$BASE_NAME" .mp4)

	BASE_NAME=${BASE_NAME##*[}
	BASE_NAME=${BASE_NAME##*]}
	while [[ $BASE_NAME == ' '* ]]; do
		BASE_NAME=${BASE_NAME:1}
	done
	if [[ $BASE_NAME == *']' ]]; then
		BASE_NAME=${BASE_NAME:0:-1}
	fi

	echo "$BASE_NAME"
}

function read_time_from_file() {
	local FNAME=$1
	if [[ $FNAME == *.xml ]]; then
		read_time_from_danmaku "$FNAME"
	else
		read_time_from_video "$FNAME"
	fi
}

function read_title_from_file() {
	local FNAME=$1
	if [[ $FNAME == *.xml ]]; then
		read_title_from_danmaku "$FNAME"
	else
		read_title_from_video "$FNAME"
	fi
}

function escape_filename() {
	local TITLE=$1
	TITLE=${TITLE//':'/'：'}
	TITLE=${TITLE//'*'/'＊'}
	TITLE=${TITLE//'?'/'？'}
	TITLE=${TITLE//'"'/'“'}
	TITLE=${TITLE//'<'/'【'}
	TITLE=${TITLE//'>'/'】'}
	TITLE=${TITLE//'|'/'｜'}
	echo "$TITLE"
}

function extname() {
	local FNAME=$1
	echo "${FNAME##*.}"
}

function ensure_symlink() {
	local LINK_FILE=$1 EXISTS_FILE=$2
	echo_debug "$LINK_FILE --> $EXISTS_FILE"

	if [[ ${EXISTS_FILE:0:1} == '/' ]]; then
		die "链接目标是绝对路径: $EXISTS_FILE"
	fi

	local REL=${LINK_FILE##$ROOT/}
	if [[ ${REL:0:1} == '/' ]]; then
		die "链接文件不在项目目录中: $LINK_FILE"
	fi
	REL="${REL//[^\/]/}"
	REL="${REL//'/'/'../'}"

	EXISTS_FILE=$(realpath -e "$EXISTS_FILE")
	REL+="${EXISTS_FILE##"$ROOT/"}"

	if [[ -L $LINK_FILE ]]; then
		if [[ $(readlink "$LINK_FILE") == "$REL" ]]; then
			return 0
		fi
		echo_debug "重新创建链接: [$LINK_FILE]: $(readlink "$LINK_FILE") ==> $REL"
		unlink "$LINK_FILE"
	elif [[ -e $LINK_FILE ]]; then
		die "目标文件存在，且不是一个符号链接: $LINK_FILE"
	fi
	ln -vs "$REL" "$LINK_FILE"
}
function float_add() {
	local CURRENT=$1 ADD
	shift
	{
		echo -n "scale=4;$CURRENT"
		for ADD; do
			echo -n " + $ADD"
		done
		echo
	} | bc | awk '{printf "%f", $0}'
}

function get_file_size() {
	stat --printf="%s" "$1"
}
