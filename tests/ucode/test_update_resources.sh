#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# update_resources.sh falls back through the download mirrors in order and
# only installs a list (and its .ver) once one of them delivered it. A stub
# wget answers the GitHub API, fails on the hosts in $HP_STUB_FAIL and logs
# every URL it is asked for.

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
echo "$url" >> "$HP_STUB_LOG"
case "$url" in
https://api.github.com/*)
	printf '[{"sha":"0123abc","commit":{"committer":{"date":"2026-10-01T00:00:00Z"}}}]'
	;;
*)
	host="${url#https://}"
	host="${host%%/*}"
	case " $HP_STUB_FAIL " in
	*" $host "*) exit 4 ;;
	esac
	printf '1.0.0.0/24\n' > "$out"
	;;
esac
STUB
chmod +x "$WORK/bin/wget"

sed -e "s#^RESOURCES_DIR=.*#RESOURCES_DIR=\"$WORK/resources\"#" \
    -e "s#^RUN_DIR=.*#RUN_DIR=\"$WORK/run\"#" \
    "$ROOT/root/etc/homeproxy/scripts/update_resources.sh" > "$WORK/update_resources.sh"

# run_update <failing hosts>: one china_ip4 update from a clean state
run_update() {
	rm -rf "$WORK/resources" "$WORK/run"
	: > "$WORK/requests.log"
	HP_STUB_FAIL="$1" HP_STUB_LOG="$WORK/requests.log" PATH="$WORK/bin:$PATH" \
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

exit $FAILED
