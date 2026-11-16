#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# dashboard_status of the rpcd object luci.homeproxy, run from the real file
# with RUN_DIR moved into $WORK: the dashboard is ready once index.html is
# unpacked, an archive without it at the top level is reported, and a failed
# download shows the error sing-box logged instead of a silent 404.

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-rpcd-dashboard-test}"

ROOT="$(cd "$ROOT" && pwd)"

rm -rf "$WORK"
mkdir -p "$WORK/run"

sed -e "s#^const RUN_DIR = '/var/run/homeproxy';#const RUN_DIR = '$WORK/run';#" \
    -e "s#'/etc/homeproxy/scripts/homeproxy.uc'#'$ROOT/root/etc/homeproxy/scripts/homeproxy.uc'#" \
    -e "s#^return { 'luci.homeproxy': methods };##" \
    "$ROOT/root/usr/share/rpcd/ucode/luci.homeproxy" > "$WORK/rpcd.uc"

cat >> "$WORK/rpcd.uc" <<TEST
const run = '$WORK/run', web = run + '/dashboard/web';
let failed = 0;
function status() { return methods.dashboard_status.call({ args: {} }); }
function check(ok, label, got) {
	if (!ok)
		failed++;
	print(ok ? 'PASS' : 'FAIL', ': rpcd dashboard: ', label, ok ? '' : sprintf(' (got %J)', got), '\n');
}

let r = status();
check(r.state === 'downloading', 'nothing downloaded and no error yet is still downloading', r);

writefile(run + '/sing-box-c.log',
	'+0000 2026-11-16 10:00:00 WARN something else\n' +
	'+0000 2026-11-16 10:00:01 ERROR update dashboard: unexpected status: 404 Not Found\n' +
	'+0000 2026-11-16 10:00:02 ERROR update dashboard: Get "https://example.com/d.zip": dial tcp: i/o timeout\n');
r = status();
check(r.state === 'failed' && r.error === 'Get "https://example.com/d.zip": dial tcp: i/o timeout', 'a failed download shows the last error', r);

system('mkdir -p ' + web + '/dist');
writefile(web + '/.etag', '"abc"');
writefile(web + '/dist/index.html', '<html></html>');
r = status();
check(r.state === 'invalid', 'an archive without a top-level index.html is reported', r);

writefile(web + '/index.html', '<html></html>');
r = status();
check(r.state === 'ready' && type(r.updated) === 'int', 'an unpacked dashboard is ready with its download time', r);

exit(failed ? 1 : 0);
TEST

ucode "$WORK/rpcd.uc"
