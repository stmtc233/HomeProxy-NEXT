#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# update_resources.sh dashboard downloads the archive itself (sing-box only
# serves the files): a GitHub archive is unpacked without its top-level
# directory and made readable for sing-box, the same archive is not unpacked
# again, a broken archive or one without a top-level index.html leaves the
# served files alone, and every outcome lands in dashboard.json for the
# client page. A stub wget serves the archives of tests/fixtures/dashboard by
# file name and fails for the names in $HP_STUB_FAIL; stub uci, ubus and
# sleep give the options, the client state and no waiting.

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-update-dashboard-test}"

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
	-O) out="$2"; shift ;;
	https://*) url="$1" ;;
	esac
	shift
done
echo "$url${https_proxy:+ (via $https_proxy)}" >> "$HP_STUB_LOG"
name="${url##*/}"
case " $HP_STUB_FAIL " in
*" $name "*) exit 8 ;;
esac
cp "$HP_STUB_ZIPS/$name" "$out"
STUB

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

printf '#!/bin/sh\n:\n' > "$WORK/bin/sleep"
chmod +x "$WORK/bin/wget" "$WORK/bin/uci" "$WORK/bin/ubus" "$WORK/bin/sleep"

unset http_proxy https_proxy

sed -e "s#^RESOURCES_DIR=.*#RESOURCES_DIR=\"$WORK/resources\"#" \
    -e "s#^RUN_DIR=.*#RUN_DIR=\"$WORK/run\"#" \
    -e "s#^SCRIPTS_DIR=.*#SCRIPTS_DIR=\"$ROOT/root/etc/homeproxy/scripts\"#" \
    "$ROOT/root/etc/homeproxy/scripts/update_resources.sh" > "$WORK/update_resources.sh"

RUN="$WORK/run"
WEB="$RUN/dashboard/web"
mkdir -p "$RUN"

# run_update <archive> [<failing archives> <client running> <mode>]
run_update() {
	: > "$WORK/requests.log"
	HP_STUB_UCI="homeproxy.config.dashboard_url=https://example.com/$1" \
	HP_STUB_FAIL="${2:-}" HP_STUB_RUNNING="${3:-0}" HP_STUB_ZIPS="$ROOT/tests/fixtures/dashboard" \
	HP_STUB_LOG="$WORK/requests.log" PATH="$WORK/bin:$PATH" \
		sh "$WORK/update_resources.sh" dashboard ${4:-}
	RC=$?
	STATUS="$(cat "$RUN/dashboard.json" 2>/dev/null)"
}

check() {
	if eval "$2"; then
		echo "PASS: update dashboard: $1"
	else
		echo "FAIL: update dashboard: $1"
		echo "	rc=$RC status=$STATUS"
		sed 's/^/	requested: /' "$WORK/requests.log"
		FAILED=1
	fi
}

state() { [ "$(echo "$STATUS" | jsonfilter -e '@.state')" = "$1" ] && [ "$(echo "$STATUS" | jsonfilter -e '@.error')" = "${2:-}" ]; }

run_update github.zip
check "a GitHub archive is installed" '[ $RC -eq 0 ] && [ "$(cat "$WEB/index.html")" = "<html>v1</html>" ] && [ -f "$WEB/assets/app.js" ]'
check "its top-level directory is dropped" '[ ! -e "$WEB/dash-gh-pages" ]'
check "the files are readable for sing-box" '[ "$(ls -l "$WEB/index.html" | cut -c1-10)" = "-rw-r--r--" ] && [ "$(ls -ld "$WEB/assets" | cut -c1-10)" = "drwxr-xr-x" ]'
check "the status says done with the download time" 'state done && [ -n "$(echo "$STATUS" | jsonfilter -e "@.updated")" ]'
check "nothing is left behind" '[ "$(ls "$RUN/dashboard" | sort | tr "\n" " ")" = "archive.time archive.ver web " ]'
check "the version line holds the URL" '[ "$(cut -d " " -f2- "$RUN/dashboard/archive.ver")" = "https://example.com/github.zip" ]'

: > "$WEB/marker"
run_update github.zip
check "the same archive is not unpacked again" '[ $RC -eq 3 ] && [ -e "$WEB/marker" ] && state done'

run_update flat.zip
check "a flat archive replaces the files" '[ $RC -eq 0 ] && [ "$(cat "$WEB/index.html")" = "<html>v2</html>" ] && [ ! -e "$WEB/marker" ] && [ ! -e "$WEB/assets" ]'

run_update nested.zip
check "an archive without a top-level index.html is refused" '[ $RC -eq 1 ] && state failed no_index'
check "and leaves the served files alone" '[ "$(cat "$WEB/index.html")" = "<html>v2</html>" ] && [ -n "$(echo "$STATUS" | jsonfilter -e "@.updated")" ]'
check "the refusal is logged" 'grep -q "no index.html at its top level" "$RUN/homeproxy.log"'

run_update broken.zip
check "a file that is not a ZIP archive is refused" '[ $RC -eq 1 ] && state failed unzip && [ "$(cat "$WEB/index.html")" = "<html>v2</html>" ] && [ ! -e "$RUN/dashboard/web.new" ]'

run_update github.zip github.zip
check "a failed download is reported" '[ $RC -eq 1 ] && state failed download && [ "$(wc -l < "$WORK/requests.log")" -eq 1 ]'

echo '{ "inbounds": [ { "tag": "direct-in" } ] }' > "$RUN/sing-box-c.json"
run_update github.zip github.zip 1
check "a download failing through the proxy is retried directly" \
	'[ "$(sed -n 2p "$WORK/requests.log")" = "https://example.com/github.zip (via http://127.0.0.1:5334)" ]'

run_update github.zip github.zip 0 boot
check "at boot a failed download is tried three times" '[ $RC -eq 1 ] && [ "$(wc -l < "$WORK/requests.log")" -eq 3 ] && state failed download'

run_update github.zip "" 0 boot
check "at boot the archive is installed too" '[ $RC -eq 0 ] && [ "$(cat "$WEB/index.html")" = "<html>v1</html>" ] && state done'

exit $FAILED
