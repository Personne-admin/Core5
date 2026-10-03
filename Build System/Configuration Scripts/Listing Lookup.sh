#!/usr/bin/env bash
set -euo pipefail

if (( $# < 2 )); then
	printf 'usage: %s <16 digit address> <listing>...\n' "$0" >&2
	exit 2
fi

address=$1
shift

awk -v target="$address" '
	function paint(line, current, addr, bytes, src, split_at, code, comment, label_len) {
		addr  = substr(line, 12, 5)
		bytes = substr(line, 19, 24)
		src   = substr(line, 43)

		split_at = index(src, ";")
		if (split_at) { code = substr(src, 1, split_at - 1); comment = substr(src, split_at) }
		else          { code = src; comment = "" }

		if (current) {
			code = CURRENT code RESET
		} else if (match(code, /^[A-Za-z_.@?][A-Za-z0-9_.@?]*:/)) {
			label_len = RLENGTH
			code = LABEL substr(code, 1, label_len) RESET substr(code, label_len + 1)
		}

		return (current ? CURRENT "=>" RESET : "  ") " " \
			ADDRESS addr RESET ": " BYTES bytes RESET code COMMENT comment RESET
	}

	BEGIN {
		if (ENVIRON["NO_COLOR"] == "") {
			RESET   = "\033[0m"
			ADDRESS = "\033[34m"
			BYTES   = "\033[33m"
			LABEL   = "\033[1;36m"
			CURRENT = "\033[1;32m"
			COMMENT = "\033[2m"
		}
	}

	FNR == 1 { file_index++ }

	{
		sub(/\r$/, "")

		has_bytes = ($0 ~ /^[0-9A-Fa-f]+: [0-9A-Fa-f][0-9A-Fa-f] /)
		is_label  = ($0 ~ /^[0-9A-Fa-f]+: +[A-Za-z_.@?][A-Za-z0-9_.@?]*:[ \t]*$/)

		if (!has_bytes && !is_label) next

		kept[++count] = $0
		owner[count]  = file_index

		if (!hit && has_bytes && toupper(substr($0, 1, 17)) == target ":") hit = count
	}

	END {
		if (!hit) exit 1
		for (i = hit - 3; i <= hit + 4; i++)
			if (i >= 1 && i <= count && owner[i] == owner[hit])
				print paint(kept[i], i == hit)
	}
' "$@"
