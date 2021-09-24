#!/usr/bin/env bash

declare -rxi FPS="30"
declare -rx TZ="Asia/Shanghai"

# 4GB
declare -r MAX_FILE_SIZE=$(echo 'scale=4;4 * 1024 * 1024 * 1024' | bc)
declare -r MAX_VIDEO_SIZE=$(echo "scale=4;0.9 * $MAX_FILE_SIZE" | bc)
declare -r MAX_AUDIO_SIZE=$(echo "scale=4;0.1 * $MAX_FILE_SIZE" | bc)

declare -ir MAX_VIDEO_BITRATE=$((1800 * 1024 * 8)) # 1800kbps
declare -ir MAX_AUDIO_BITRATE=$((320 * 1024 * 8)) # 320kbps
