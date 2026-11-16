#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# dashboard_status / dashboard_update of the rpcd object luci.homeproxy, run
# from the real file with HP_DIR and RUN_DIR moved into $WORK: the status is
# what update_resources.sh wrote, a download whose process is gone is shown
# as interrupted, and an update starts the script in the background.

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-rpcd-dashboard-test}"

ROOT="$(cd "$ROOT" && pwd)"

rm -rf "$WORK"
mkdir -p "$WORK/run" "$WORK/hp/scripts"

# stands in for update_resources.sh: records its arguments
cat > "$WORK/hp/scripts/update_resources.sh" <<STUB
#!/bin/sh
echo "\$*" > "$WORK/run/called"
STUB
chmod +x "$WORK/hp/scripts/update_resources.sh"

sed -e "s#^const HP_DIR = '/etc/homeproxy';#const HP_DIR = '$WORK/hp';#" \
    -e "s#^const RUN_DIR = '/var/run/homeproxy';#const RUN_DIR = '$WORK/run';#" \
    -e "s#'/etc/homeproxy/scripts/homeproxy.uc'#'$ROOT/root/etc/homeproxy/scripts/homeproxy.uc'#" \
    -e "s#^return { 'luci.homeproxy': methods };##" \
    "$ROOT/root/usr/share/rpcd/ucode/luci.homeproxy" > "$WORK/rpcd.uc"

cat >> "$WORK/rpcd.uc" <<TEST
const run = '$WORK/run';
let failed = 0;
function call(method) { return methods[method].call({ args: {} }); }
function check(ok, label, got) {
	if (!ok)
		failed++;
	print(ok ? 'PASS' : 'FAIL', ': rpcd dashboard: ', label, ok ? '' : sprintf(' (got %J)', got), '\n');
}

let r = call('dashboard_status');
check(r.state === 'none', 'no status file is not downloaded yet', r);

writefile(run + '/dashboard.json', '{"state":"failed","error":"no_index","updated":1700000000}\n');
r = call('dashboard_status');
check(r.state === 'failed' && r.error === 'no_index' && r.updated === 1700000000, 'the status of the script is passed on', r);

writefile(run + '/dashboard.json', '{"state":"running","error":"","updated":null}\n');
r = call('dashboard_status');
check(r.state === 'failed' && r.error === 'interrupted', 'a download nobody runs any more is interrupted', r);

/* the script holds the lock while it runs */
const holder = popen('flock ' + run + '/update_resources-dashboard.lock sleep 3', 'r');
system('sleep 1');
r = call('dashboard_status');
check(r.state === 'running', 'a running download is running', r);
holder.close();

writefile(run + '/dashboard.json', '{broken');
check(call('dashboard_status').state === 'none', 'a broken status file is ignored', null);

r = call('dashboard_update');
system('sleep 1');
check(r.result === true && trim(readfile(run + '/called') || '') === 'dashboard', 'an update starts the script', readfile(run + '/called'));

exit(failed ? 1 : 0);
TEST

ucode "$WORK/rpcd.uc"
