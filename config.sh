#!/usr/bin/env bash

declare -rxi FPS="30"
declare -rx TZ="Asia/Shanghai"

# 4GB
declare -r MAX_FILE_SIZE=$(echo 'scale=4;4 * 1024 * 1024 * 1024' | bc)
declare -r MAX_VIDEO_SIZE=$(echo "scale=4;0.9 * $MAX_FILE_SIZE" | bc)
declare -r MAX_AUDIO_SIZE=$(echo "scale=4;0.1 * $MAX_FILE_SIZE" | bc)

declare -ir MAX_VIDEO_BITRATE=$((20000 * 1024)) # ???kbps
declare -ir MAX_AUDIO_BITRATE=$((320 * 1024))  # 320kbps

if [[ ! ${CACHE_DIR:-} ]] && [[ "${SYSTEM_COMMON_CACHE:-}" ]]; then
	CACHE_DIR="$SYSTEM_COMMON_CACHE/live-encoding"
fi
