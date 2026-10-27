#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# scripts/defaults.sh and DEFAULTS in homeproxy.uc must agree: every
# HP_DEFAULT_<OPTION> of the shell side names an option that DEFAULTS holds
# exactly once, with the same value. The infra section is not meant to be
# edited, so its fallbacks must equal the shipped config option for option.

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
SCRIPTS="$ROOT/root/etc/homeproxy/scripts"
FAILED=0

# one "<option> <value>" line per DEFAULTS entry
UC_DEFAULTS="$(ucode -L "$SCRIPTS" -e 'import { DEFAULTS } from "homeproxy";
	for (let s in DEFAULTS) for (let o in DEFAULTS[s]) print(o, " ", DEFAULTS[s][o], "\n");')" || {
	echo "FAIL: cannot read DEFAULTS from homeproxy.uc"
	exit 1
}

. "$SCRIPTS/defaults.sh"

for var in $(sed -n 's/^\(HP_DEFAULT_[A-Z0-9_]*\)=.*/\1/p' "$SCRIPTS/defaults.sh"); do
	opt="$(echo "${var#HP_DEFAULT_}" | tr 'A-Z' 'a-z')"
	eval "sh_value=\"\$$var\""
	matches="$(echo "$UC_DEFAULTS" | grep -c "^$opt ")"
	uc_value="$(echo "$UC_DEFAULTS" | sed -n "s/^$opt //p")"
	if [ "$matches" -ne 1 ]; then
		echo "FAIL: $var: DEFAULTS has $matches entries named $opt"
		FAILED=1
	elif [ "$sh_value" != "$uc_value" ]; then
		echo "FAIL: $var is '$sh_value' but DEFAULTS.$opt is '$uc_value'"
		FAILED=1
	fi
done

[ "$FAILED" -eq 0 ] && echo "PASS: defaults.sh agrees with DEFAULTS in homeproxy.uc"

if ucode -L "$SCRIPTS" -e 'import { DEFAULTS } from "homeproxy"; import { cursor } from "uci";
	const uci = cursor(ARGV[0]), shipped = uci.get_all("homeproxy", "infra"), bad = [];
	for (let o in DEFAULTS.infra)
		if (shipped[o] !== DEFAULTS.infra[o])
			push(bad, sprintf("DEFAULTS.infra.%s is %J but the shipped config has %J", o, DEFAULTS.infra[o], shipped[o]));
	for (let o, v in shipped)
		if (substr(o, 0, 1) !== "." && o !== "__warning" && length(v) && !(o in DEFAULTS.infra))
			push(bad, sprintf("shipped infra option %s=%J has no DEFAULTS.infra entry", o, v));
	for (let b in bad) print("FAIL: ", b, "\n");
	exit(length(bad) ? 1 : 0);' "$ROOT/root/etc/config"; then
	echo "PASS: DEFAULTS.infra matches the infra section of the shipped config"
else
	FAILED=1
fi

exit $FAILED
