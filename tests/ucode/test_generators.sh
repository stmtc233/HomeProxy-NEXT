#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-generator-test}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

run_case() {
	name="$1"
	fixture="$2"
	generator="$3"
	outfile="$4"
	plugins="$5"
	expect_error="$6"
	template="$7"
	dir="$WORK/$name"

	rm -rf "$dir"
	mkdir -p "$dir/config" "$dir/run" "$dir/scripts" "$dir/ruleset"

	if grep -q "__RULESET_DIR__" "$fixture"; then
		printf '%s' '{"version":1,"rules":[{"domain_suffix":["example.com"]}]}' > "$dir/ruleset/src.json"
		if ! sing-box rule-set compile "$dir/ruleset/src.json" -o "$dir/ruleset/test.srs"; then
			echo "FAIL: $name: could not compile the local rule-set fixture"
			FAILED=1
			return
		fi
		sed "s#__RULESET_DIR__#$dir/ruleset#" "$fixture" > "$dir/config/homeproxy"
	else
		cp "$fixture" "$dir/config/homeproxy"
	fi

	sed -e "s#^export const HP_DIR = '/etc/homeproxy';#export const HP_DIR = '$dir';#" \
	    -e "s#^export const RUN_DIR = '/var/run/homeproxy';#export const RUN_DIR = '$dir/run';#" \
	    "$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$dir/scripts/homeproxy.uc"

	# the WAN DNS lookup is stubbed out so the output (and the golden) does not
	# depend on the upstream DNS of the host running the suite
	wan_stub="s#ubus.call('network.interface', 'status', {'interface': 'wan'})#null#"
	sed -e "s#const uci = cursor();#const uci = cursor('$dir/config');#" -e "$wan_stub" \
	    "$ROOT/root/etc/homeproxy/scripts/$generator" > "$dir/scripts/$generator"

	[ -n "$plugins" ] && cp -R "$plugins" "$dir/custom"

	mkdir -p "$dir/scripts/client"
	for module in "$ROOT/root/etc/homeproxy/scripts/client/"*.uc; do
		sed -e "$wan_stub" "$module" > "$dir/scripts/client/${module##*/}"
	done

	sed -e "s#const uci = cursor();#const uci = cursor('$dir/config');#" \
	    "$ROOT/root/etc/homeproxy/scripts/apply_template.uc" > "$dir/scripts/apply_template.uc"
	if [ -n "$template" ] && ! ( cd "$dir/scripts" && ucode apply_template.uc "$template" ); then
		echo "FAIL: $name: apply_template.uc $template exited non-zero"
		FAILED=1
		return
	fi

	if [ -n "$expect_error" ]; then
		if ( cd "$dir/scripts" && ucode "$generator" ) > "$dir/generator.log" 2>&1; then
			echo "FAIL: $name: $generator accepted a config it should refuse"
			FAILED=1
		elif grep -qF -- "$expect_error" "$dir/generator.log"; then
			echo "PASS: $name: $generator refused it"
		else
			echo "FAIL: $name: $generator failed without '$expect_error':"
			cat "$dir/generator.log"
			FAILED=1
		fi
		return
	fi

	if ! ( cd "$dir/scripts" && ucode "$generator" ); then
		echo "FAIL: $name: $generator exited non-zero"
		FAILED=1
		return
	fi

	if [ ! -f "$dir/run/$outfile" ]; then
		echo "FAIL: $name: $outfile was not generated"
		FAILED=1
		return
	fi

	if ! sing-box check --config "$dir/run/$outfile"; then
		echo "FAIL: $name: sing-box rejected the generated $outfile"
		FAILED=1
		return
	fi

	echo "PASS: $name ($(wc -c < "$dir/run/$outfile") bytes)"
}

run_case client "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json

check_golden() {
	name="$1"
	outfile="$2"
	golden="$ROOT/tests/snapshots/$name.generated.json"
	normalized="$WORK/$name/normalized.json"

	sed "s#$WORK/$name#__WORKDIR__#g" "$WORK/$name/run/$outfile" > "$normalized"
	if [ ! -f "$golden" ]; then
		echo "FAIL: $name: golden snapshot $golden is missing (normalized output: $normalized)"
		FAILED=1
	elif cmp -s "$golden" "$normalized"; then
		echo "PASS: $name generator matches the golden snapshot"
	else
		echo "FAIL: $name generator output differs from the golden snapshot (normalized output: $normalized)"
		if command -v diff > "/dev/null" 2>&1; then
			diff -u "$golden" "$normalized" | head -40
		fi
		FAILED=1
	fi
}

check_golden client sing-box-c.json

run_case client-sub "$ROOT/tests/fixtures/generators/client-sub.uci" generate_client.uc sing-box-c.json
CLIENT_SUB_OUT="$WORK/client-sub/run/sing-box-c.json"
assert_sub() {
	label="$1"
	pattern="$2"
	if grep -q -- "$pattern" "$CLIENT_SUB_OUT"; then
		echo "PASS: $label"
	else
		echo "FAIL: $label (no match for: $pattern)"
		FAILED=1
	fi
}
assert_sub "client-sub: n_anytls expanded from subscription" '"tag": "anytls"'
assert_sub "client-sub: n_ss expanded from subscription" '"tag": "ss"'

# group_field <config> <tag> <field>: a field of an outbound, lists joined by commas
group_field() {
	ucode -e "import { readfile } from 'fs';
		for (let o in json(readfile('$1')).outbounds)
			if (o.tag == '$2')
				print(type(o['$3']) == 'array' ? join(',', o['$3']) : o['$3']);"
}
assert_group() {
	label="$1"
	got="$(group_field "$CLIENT_SUB_OUT" "$2" "$3")"
	if [ "$got" = "$4" ]; then
		echo "PASS: $label"
	else
		echo "FAIL: $label (got: $got)"
		FAILED=1
	fi
}
ALL_NODES="anytls,vless-reality-ws,vmess-http,trojan-grpc,ss,hy2,snell,http,socks,shadowtls"
assert_group "client-sub: a subscription expands to its own nodes" auto outbounds "anytls,ss"
assert_group "client-sub: all-nodes expands to every node in order" all outbounds "$ALL_NODES"
assert_group "client-sub: a selector takes all-nodes next to other members" pick outbounds "all,$ALL_NODES,direct-out"
assert_group "client-sub: a node reached through all-nodes can be the default" pick default "http"

run_case custom "$ROOT/tests/fixtures/generators/custom.uci" generate_client.uc sing-box-c.json
run_case custom_no_default "$ROOT/tests/fixtures/generators/custom-no-default-outbound.uci" generate_client.uc sing-box-c.json

CUSTOM_OUT="$WORK/custom_no_default/run/sing-box-c.json"

assert_json() {
	label="$1"
	pattern="$2"
	if grep -q -- "$pattern" "$CUSTOM_OUT"; then
		echo "PASS: $label"
	else
		echo "FAIL: $label (no match for: $pattern)"
		FAILED=1
	fi
}

assert_json "custom/no-default: a global domain resolver is declared" '"default_domain_resolver"'
assert_json "custom/no-default: the user DNS server survived" '"tag": "DNS_Server_Proxy"'
assert_json "custom/no-default: the user DNS rule survived" 'dns-rule-marker.example.com'
assert_json "custom/no-default: the hosts DNS server is emitted" '"hosts-marker.example.com"'
assert_json "custom/no-default: the dhcp DNS server is emitted" '"type": "dhcp"'
assert_json "custom/no-default: the respond action is emitted" '"action": "respond"'
assert_json "custom/no-default: the realm outbound carries its realm" '"realm_id": "hp-test"'
assert_json "custom/no-default: the urltest group survived" '"tag": "Routing_Node_Proxy"'
assert_json "custom/no-default: its member nodes survived" '"tag": "hk"'
assert_json "custom/no-default: the user rule-set survived" '"tag": "rs-cn"'
assert_json "custom/no-default: the user routing rule survived" 'routing-rule-marker.example.com'
assert_json "custom/no-default: dns.final follows default_server" '"final": "default-dns"'

run_case custom_labels "$ROOT/tests/fixtures/generators/custom-labels.uci" generate_client.uc sing-box-c.json
CUSTOM_OUT="$WORK/custom_labels/run/sing-box-c.json"
assert_json "custom/labels: a node is tagged by its label" '"tag": "🇭🇰 香港 01"'
assert_json "custom/labels: a duplicate label is suffixed" '"tag": "🇭🇰 香港 01 #2"'
assert_json "custom/labels: a label equal to a built-in tag is suffixed" '"tag": "direct-out #2"'
assert_json "custom/labels: a node without label keeps the section name" '"tag": "cfg-n_nolabel-out"'
assert_json "custom/labels: the urltest group is tagged by its label" '"tag": "🚀 自动选择"'
assert_json "custom/labels: a routing rule points at the node label" '"outbound": "🇭🇰 香港 01"'
assert_json "custom/labels: a DNS server is tagged by its label" '"tag": "🌐 谷歌 DNS ✈️"'
assert_json "custom/labels: a DNS label equal to a built-in tag is suffixed" '"tag": "default-dns #2"'
assert_json "custom/labels: a DNS server without label keeps the section name" '"tag": "cfg-ds_nolabel-dns"'
assert_json "custom/labels: dns.final points at the DNS label" '"final": "🌐 谷歌 DNS ✈️"'
assert_json "custom/labels: extra rule-set tags are kept verbatim" '"geosite"$'
assert_json "custom/labels: a rule-set label clashing with an extra tag is suffixed" '"tag": "geosite #2"'

run_case custom_selector_loop "$ROOT/tests/fixtures/generators/custom-selector-loop.uci" generate_client.uc sing-box-c.json "" \
	"Selector loop sel-a -> sel-b -> sel-a"

run_case rules "$ROOT/tests/fixtures/generators/rules.uci" generate_client.uc sing-box-c.json
check_golden rules sing-box-c.json

for name in tun custom-extras; do
	run_case "$name" "$ROOT/tests/fixtures/generators/$name.uci" generate_client.uc sing-box-c.json
	check_golden "$name" sing-box-c.json
done

# bypass_cn_traffic rules Global out: the mode is skipped with its rules, and
# a Global default mode falls back to the first other one
mkdir -p "$WORK/bypass-cn-fixture"
cp "$ROOT/tests/fixtures/generators/custom-extras.uci" "$WORK/bypass-cn-fixture/homeproxy"
uci -c "$WORK/bypass-cn-fixture" -q batch <<-EOF
	set homeproxy.routing.bypass_cn_traffic=1
	set homeproxy.routing.default_mode=m_global
	commit homeproxy
EOF
run_case bypass_cn "$WORK/bypass-cn-fixture/homeproxy" generate_client.uc sing-box-c.json
BYPASS_OUT="$WORK/bypass_cn/run/sing-box-c.json"
if [ -f "$BYPASS_OUT" ] && ! grep -q 'Global' "$BYPASS_OUT" && grep -q '"default_mode": "Rule"' "$BYPASS_OUT" \
	&& grep -q '"clash_mode": "Rule"' "$BYPASS_OUT" && grep -q '"clash_mode": "RuleAllowAds"' "$BYPASS_OUT"; then
	echo "PASS: bypass_cn: Global is gone from the rules and the default mode, the other modes stay"
else
	echo "FAIL: bypass_cn: Global is still there, or the other modes went with it"
	FAILED=1
fi

# the default template, seeded into a fresh install with two nodes
run_case template "$ROOT/tests/fixtures/generators/template.uci" generate_client.uc sing-box-c.json "" "" seed
check_golden template sing-box-c.json

TPL_UCI="uci -c $WORK/template/config -q"
$TPL_UCI delete homeproxy.rr_rule_ads
$TPL_UCI set homeproxy.rr_user=routing_rule
$TPL_UCI commit homeproxy
( cd "$WORK/template/scripts" && ucode apply_template.uc seed )
if ! $TPL_UCI get homeproxy.rr_rule_ads > "/dev/null" && $TPL_UCI get homeproxy.rr_user > "/dev/null"; then
	echo "PASS: template: seeding leaves a config with routing modes alone"
else
	echo "FAIL: template: seeding changed a config that has routing sections"
	FAILED=1
fi
( cd "$WORK/template/scripts" && ucode apply_template.uc )
if $TPL_UCI get homeproxy.rr_rule_ads > "/dev/null" && ! $TPL_UCI get homeproxy.rr_user > "/dev/null"; then
	echo "PASS: template: applying it replaces every routing section"
else
	echo "FAIL: template: applying it did not replace the routing sections"
	FAILED=1
fi

# a config from before the modes: its rules move into Custom, the template joins them
run_case migration "$ROOT/tests/fixtures/generators/migration.uci" generate_client.uc sing-box-c.json "" "" seed
MIG_UCI="uci -c $WORK/migration/config -q"
mig_get() {
	$MIG_UCI get "homeproxy.$1" 2>"/dev/null"
}
if [ "$(mig_get m_custom.label)" = "Custom" ] && [ "$(mig_get m_custom.default_outbound)" = "rn_mine" ] \
	&& [ "$(mig_get m_custom.default_server)" = "ds_mine" ] && [ "$(mig_get routing.default_mode)" = "m_custom" ] \
	&& [ "$(mig_get rr_mine.routing_mode)" = "m_custom" ] && [ "$(mig_get dr_mine.routing_mode)" = "m_custom" ] \
	&& [ -z "$(mig_get rr_mine.clash_mode)" ] && [ -z "$(mig_get routing.default_outbound)" ] \
	&& [ -z "$(mig_get dns.default_server)" ] && [ "$(mig_get m_rule.label)" = "Rule" ] \
	&& grep -q '"default_mode": "Custom"' "$WORK/migration/run/sing-box-c.json"; then
	echo "PASS: migration: the old rules and fallbacks make the Custom mode, next to the template"
else
	echo "FAIL: migration: the old config did not end up in the Custom mode next to the template"
	$MIG_UCI show homeproxy
	FAILED=1
fi

run_case server "$ROOT/tests/fixtures/generators/server.uci" generate_server.uc sing-box-s.json
check_golden server sing-box-s.json

# custom plugins (tests/fixtures/plugins/<mode>) on top of the golden cases
check_plugins() {
	mode="$1"
	name="$2"
	outfile="$3"
	kind="$4"
	sed "s#$WORK/plugins-$mode#__WORKDIR__#g" "$WORK/plugins-$mode/run/$outfile" > "$WORK/plugins-$mode/normalized.json"
	ucode "$ROOT/tests/ucode/check_plugins.uc" "$mode" "$WORK/plugins-$mode/normalized.json" \
		"$ROOT/tests/snapshots/$name.generated.json" "$WORK/plugins-$mode/run/plugins-$kind.json" || FAILED=1
}
run_case plugins-client "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json "$ROOT/tests/fixtures/plugins/client"
check_plugins client client sing-box-c.json client
run_case plugins-fallback "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json "$ROOT/tests/fixtures/plugins/fallback"
check_plugins fallback client sing-box-c.json client
run_case plugins-server "$ROOT/tests/fixtures/generators/server.uci" generate_server.uc sing-box-s.json "$ROOT/tests/fixtures/plugins/server"
check_plugins server server sing-box-s.json server

exit $FAILED
