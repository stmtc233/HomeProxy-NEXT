#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# update_resources.sh falls back through the download mirrors in order and
# only installs a list (and its .ver) once one of them delivered it, and
# retries a download directly (through the client's direct-in) when it fails
# through the proxy. A stub wget answers the GitHub API, fails on the hosts in
# $HP_STUB_FAIL ($HP_STUB_FAIL_DIRECT when it is sent to direct-in) and logs
# every URL it is asked for; stub uci and ubus give the options and whether
# the client is running.

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-update-resources-test}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

rm -rf "$WORK"
mkdir -p "$WORK/bin"

cat > "$WORK/bin/wget" <<'STUB'
#!/bin/sh
out=""
url=""
while [ $# -gt 0 ]; do
	case "$1" in
	-O-) out="-" ;;
	-O) out="$2"; shift ;;
	https://*) url="$1" ;;
	esac
	shift
done
if [ -n "${https_proxy:-}" ]; then
	echo "$url (via $https_proxy)" >> "$HP_STUB_LOG"
	fail="$HP_STUB_FAIL_DIRECT"
else
	echo "$url" >> "$HP_STUB_LOG"
	fail="$HP_STUB_FAIL"
fi
host="${url#https://}"
host="${host%%/*}"
case " $fail " in
*" $host "*) exit 4 ;;
esac
case "$url" in
https://api.github.com/*)
	body='[{"sha":"0123abc","commit":{"committer":{"date":"2026-10-01T00:00:00Z"}}}]'
	;;
*)
	body='1.0.0.0/24'
	;;
esac
if [ "$out" = "-" ]; then
	printf '%s\n' "$body"
else
	printf '%s\n' "$body" > "$out"
fi
STUB

# uci -q get <key>: the "<key>=<value>" lines of $HP_STUB_UCI
cat > "$WORK/bin/uci" <<'STUB'
#!/bin/sh
value="$(printf '%s\n' "$HP_STUB_UCI" | sed -n "s/^$3=//p")"
[ -n "$value" ] || exit 1
echo "$value"
STUB

cat > "$WORK/bin/ubus" <<'STUB'
#!/bin/sh
[ "$HP_STUB_RUNNING" = "1" ] || exit 4
echo '{"homeproxy":{"instances":{"sing-box-c":{"running":true}}}}'
STUB
chmod +x "$WORK/bin/wget" "$WORK/bin/uci" "$WORK/bin/ubus"

# the stub tells direct-in by these
unset http_proxy https_proxy

sed -e "s#^RESOURCES_DIR=.*#RESOURCES_DIR=\"$WORK/resources\"#" \
    -e "s#^RUN_DIR=.*#RUN_DIR=\"$WORK/run\"#" \
    -e "s#^SCRIPTS_DIR=.*#SCRIPTS_DIR=\"$ROOT/root/etc/homeproxy/scripts\"#" \
    "$ROOT/root/etc/homeproxy/scripts/update_resources.sh" > "$WORK/update_resources.sh"

# run_update <failing hosts> [<failing hosts directly> <client running> <uci>]:
# one china_ip4 update from a clean state
run_update() {
	rm -rf "$WORK/resources" "$WORK/run"
	mkdir -p "$WORK/run"
	[ "${3:-0}" = "1" ] && echo '{ "inbounds": [ { "tag": "direct-in" } ] }' > "$WORK/run/sing-box-c.json"
	: > "$WORK/requests.log"
	HP_STUB_FAIL="$1" HP_STUB_FAIL_DIRECT="${2:-}" HP_STUB_RUNNING="${3:-0}" HP_STUB_UCI="${4:-}" \
	HP_STUB_LOG="$WORK/requests.log" PATH="$WORK/bin:$PATH" \
		sh "$WORK/update_resources.sh" china_ip4
	RC=$?
}

check() {
	if eval "$2"; then
		echo "PASS: $1"
	else
		echo "FAIL: $1"
		sed 's/^/	requested: /' "$WORK/requests.log"
		FAILED=1
	fi
}

installed='[ "$(cat "$WORK/resources/china_ip4.txt" 2>/dev/null)" = "1.0.0.0/24" ] && [ "$(cat "$WORK/resources/china_ip4.ver")" = "2026-10-01 0123abc" ]'

run_update ""
check "first mirror serves the list" "[ $RC -eq 0 ] && $installed"
check "no other mirror is tried once one succeeds" \
	'[ "$(sed -n 2p "$WORK/requests.log")" = "https://fastly.jsdelivr.net/gh/1715173329/IPCIDR-CHINA@0123abc/ipv4.txt" ] && [ "$(wc -l < "$WORK/requests.log")" -eq 2 ]'

run_update "fastly.jsdelivr.net"
check "a failing mirror falls back to the next one" "[ $RC -eq 0 ] && $installed"
check "the fallback order is fastly, then gcore" \
	'[ "$(sed -n 3p "$WORK/requests.log")" = "https://gcore.jsdelivr.net/gh/1715173329/IPCIDR-CHINA@0123abc/ipv4.txt" ]'
check "the log names the mirror that delivered" 'grep -q "Downloaded from gcore.jsdelivr.net" "$WORK/run/homeproxy.log"'

run_update "fastly.jsdelivr.net gcore.jsdelivr.net cdn.jsdelivr.net"
check "raw.githubusercontent.com is the last resort" "[ $RC -eq 0 ] && $installed"
check "the raw URL uses the <repo>/<sha>/<file> shape" \
	'[ "$(tail -n 1 "$WORK/requests.log")" = "https://raw.githubusercontent.com/1715173329/IPCIDR-CHINA/0123abc/ipv4.txt" ]'

run_update "fastly.jsdelivr.net gcore.jsdelivr.net cdn.jsdelivr.net raw.githubusercontent.com"
check "every mirror failing is reported as a failure" "[ $RC -eq 1 ]"
check "nothing is installed when every mirror fails" \
	'[ ! -e "$WORK/resources/china_ip4.txt" ] && [ ! -e "$WORK/resources/china_ip4.ver" ] && [ ! -e "$WORK/run/ipv4.txt" ]'
check "the failure is logged" 'grep -q "Download failed on every mirror" "$WORK/run/homeproxy.log"'

DIRECT="(via http://127.0.0.1:5334)"
FASTLY="https://fastly.jsdelivr.net/gh/1715173329/IPCIDR-CHINA@0123abc/ipv4.txt"

run_update "fastly.jsdelivr.net" "" 1
check "a mirror failing through the proxy is retried directly" "[ $RC -eq 0 ] && $installed"
check "the direct retry goes to direct-in before the next mirror" \
	'[ "$(sed -n 3p "$WORK/requests.log")" = "$FASTLY $DIRECT" ] && [ "$(wc -l < "$WORK/requests.log")" -eq 3 ]'
check "the direct retry is logged" 'grep -q "fastly.jsdelivr.net.* through the proxy (wget exit 4), retrying directly" "$WORK/run/homeproxy.log"'

run_update "api.github.com" "" 1
check "the version check is retried directly too" \
	'[ $RC -eq 0 ] && [ "$(sed -n 2p "$WORK/requests.log")" = "https://api.github.com/repos/1715173329/IPCIDR-CHINA/commits?sha=master&path=ipv4.txt&per_page=1 $DIRECT" ] && [ ! -e "$WORK/run/update_resources-china_ip4.json" ]'

run_update "fastly.jsdelivr.net" "fastly.jsdelivr.net" 1
check "a mirror failing both ways falls back to the next one" \
	'[ $RC -eq 0 ] && [ "$(sed -n 4p "$WORK/requests.log")" = "https://gcore.jsdelivr.net/gh/1715173329/IPCIDR-CHINA@0123abc/ipv4.txt" ]'

run_update "fastly.jsdelivr.net" "" 1 "homeproxy.subscription.update_fallback_direct=0"
check "no direct retry with update_fallback_direct off" \
	'[ $RC -eq 0 ] && ! grep -q "via" "$WORK/requests.log" && [ "$(wc -l < "$WORK/requests.log")" -eq 3 ]'

run_update "fastly.jsdelivr.net" "" 0
check "no direct retry while the client is not running" '[ $RC -eq 0 ] && ! grep -q "via" "$WORK/requests.log"'

run_update "" "" 1 "homeproxy.subscription.update_via_proxy=0
homeproxy.infra.direct_port=6000"
check "update_via_proxy off installs the list" "[ $RC -eq 0 ] && $installed"
check "update_via_proxy off downloads everything through direct-in" \
	'[ "$(grep -c "(via http://127.0.0.1:6000)$" "$WORK/requests.log")" -eq 2 ] && [ "$(wc -l < "$WORK/requests.log")" -eq 2 ]'

exit $FAILED
