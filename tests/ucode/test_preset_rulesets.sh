#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# migrate_config.uc adds the preset CN rule-sets of the shipped config to an
# upgraded config, once: identical to the shipped sections, not again after
# the user deleted them, and never over a section of the same name.

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-preset-rulesets-test}"

ROOT="$(cd "$ROOT" && pwd)"
SCRIPTS="$ROOT/root/etc/homeproxy/scripts"
FAILED=0

rm -rf "$WORK"
mkdir -p "$WORK/config"
sed "s#const uci = cursor();#const uci = cursor('$WORK/config');#" "$SCRIPTS/migrate_config.uc" > "$WORK/migrate_config.uc"

presets() {
	for s in geoip_cn geosite_cn; do
		uci -c "$WORK/config" -q show "homeproxy.$s"
	done
}

migrate() {
	ucode -L "$SCRIPTS" "$WORK/migrate_config.uc"
}

check() {
	if [ "$2" = "$3" ]; then
		echo "PASS: $1"
	else
		echo "FAIL: $1"
		echo "  expected: $(echo "$2" | tr '\n' ' ')"
		echo "  got:      $(echo "$3" | tr '\n' ' ')"
		FAILED=1
	fi
}

cp "$ROOT/root/etc/config/homeproxy" "$WORK/config/homeproxy"
shipped="$(presets)"
[ -n "$shipped" ] || { echo "FAIL: the shipped config has no preset rule-sets"; exit 1; }

# an install from before the presets: no sections, no migration flag
uci -c "$WORK/config" delete homeproxy.geoip_cn
uci -c "$WORK/config" delete homeproxy.geosite_cn
uci -c "$WORK/config" delete homeproxy.migration.preset_rulesets
uci -c "$WORK/config" commit homeproxy
migrate
check "an upgraded config gets the shipped preset rule-sets" "$shipped" "$(presets)"
check "the migration is recorded" "1" "$(uci -c "$WORK/config" -q get homeproxy.migration.preset_rulesets)"

uci -c "$WORK/config" delete homeproxy.geoip_cn
uci -c "$WORK/config" commit homeproxy
migrate
check "a deleted preset stays deleted" "" "$(uci -c "$WORK/config" -q show homeproxy.geoip_cn)"

uci -c "$WORK/config" set homeproxy.geoip_cn=ruleset
uci -c "$WORK/config" set homeproxy.geoip_cn.label='mine'
uci -c "$WORK/config" delete homeproxy.migration.preset_rulesets
uci -c "$WORK/config" commit homeproxy
migrate
check "a section of the same name is left alone" "homeproxy.geoip_cn=ruleset
homeproxy.geoip_cn.label='mine'" "$(uci -c "$WORK/config" -q show homeproxy.geoip_cn)"

exit $FAILED
