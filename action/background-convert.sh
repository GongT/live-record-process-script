#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $* == "stop" ]]; then
	if systemctl is-active -q live-compress.service; then
		systemctl stop live-compress.service
	fi
	systemctl reset-failed live-compress.service &>/dev/null || true
	exit 0
fi

if ! systemctl is-active -q live-compress.service; then
	systemctl reset-failed live-compress.service &>/dev/null || true
	cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
	systemd-run --nice=-10 --same-dir --unit=live-compress.service bash --login "$(pwd)/convert.sh" "$@"
fi

journalctl -f -ocat -u live-compress.service --lines=0
