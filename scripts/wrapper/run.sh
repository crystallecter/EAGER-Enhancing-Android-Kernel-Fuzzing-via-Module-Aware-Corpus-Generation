#!/usr/bin/env bash


while [[ $# -gt 0 ]]; do
	case "$1" in 
		-o)
			shift
			out_file="$1"
			echo -n "$out_file"
			;;
		*)
			shift
			;;
	esac
done