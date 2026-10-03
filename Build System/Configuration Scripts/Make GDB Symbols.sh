#!/usr/bin/env bash
set -euo pipefail

if (( $# != 5 )); then
	printf 'usage: %s <objcopy> <binary> <listing> <output> <load address>\n' "$0" >&2
	exit 2
fi

objcopy=$1
binary=$2
listing=$3
output=$4
load_address=$5

temporary="${output}.tmp"
trap 'rm -f -- "$temporary"' EXIT

arguments=(-I binary -O elf32-i386 -B i386 --rename-section .data=.text,alloc,load,readonly,code,contents --wildcard --strip-symbol '_binary_*')
current_global=
symbol_count=0

while IFS= read -r line; do
	# matches the listing format extracting the 16 digit address and name from the listing file
	if [[ $line =~ ^([[:xdigit:]]{16}):.*[[:space:]]([A-Za-z_.@?][A-Za-z0-9_.@?]*):[[:space:]]*$ ]]; then
		address=${BASH_REMATCH[1]}
		name=${BASH_REMATCH[2]}

		if [[ $name == .* ]]; then
			[[ -n $current_global ]] || continue
			name="${current_global}${name}"
		else
			current_global=$name
		fi

		offset=$((16#$address - load_address))
		(( offset >= 0 )) || continue

		printf -v offset_hex '%X' "$offset"
		arguments+=(--add-symbol "${name}=.text:0x${offset_hex},global")

		((symbol_count += 1))
	fi
done < "$listing"

if (( symbol_count == 0 )); then
	printf '%s: no address labels found in %s\n' "$0" "$listing" >&2
	exit 1
fi

"$objcopy" "${arguments[@]}" "$binary" "$temporary"
mv -f -- "$temporary" "$output"
trap - EXIT
