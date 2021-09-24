#!/usr/bin/env bash

function callstack() {
	local -i SKIP=${1-1}
	local -i i
	for i in $(seq $SKIP $((${#FUNCNAME[@]} - 1))); do
		if [[ ${BASH_SOURCE[$((i + 1))]+found} == "found" ]]; then
			echo "  $i: ${BASH_SOURCE[$((i + 1))]}:${BASH_LINENO[$i]} ${FUNCNAME[$i]}()"
		else
			echo "  $i: ${FUNCNAME[$i]}()"
		fi
	done
}

function _exit_handle() {
	RET=$?
	echo -ne "\e[0m"
	if [[ $RET -ne 0 ]]; then
		callstack 0
	fi
	exit $RET
}

trap _exit_handle EXIT

function error() {
	echo_error "$*"
	return 1
}
function die() {
	echo_error "$*"
	exit 1
}
function echo_debug() {
	echo -e "\e[2m$*\e[0m" >&2
}
function echo_info() {
	local A=$1
	shift
	echo -e "\e[38;5;11m$A\e[0m $*" >&2
}
function echo_error() {
	echo -e "\e[38;5;9m$*\e[0m" >&2
}
function echo_success() {
	local A=$1
	shift
	echo -e "\e[38;5;10m$A\e[0m $*" >&2
}
