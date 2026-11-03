#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Exercise the production updater and its rpcd methods with real UCI, files,
# locks and processes, and deterministic network, parser and service
# boundaries. Protocol parsing has its own suite.
set -eu
ROOT="$(cd "${1:-.}" && pwd)"
WORK="${2:-/tmp/hp-subscriptions-test}"
rm -rf "$WORK"
mkdir -p "$WORK/config" "$WORK/run" "$WORK/hp/scripts"
SCRIPTS="$WORK/hp/scripts"
fail() { echo "FAIL: $*"; exit 1; }

# The status file path and its reader come from the production module.
sed "s#^export const RUN_DIR = '/var/run/homeproxy';#export const RUN_DIR = '$WORK/run';#" \
	"$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$SCRIPTS/homeproxy.uc"
grep -q "RUN_DIR = '$WORK/run'" "$SCRIPTS/homeproxy.uc" || fail 'RUN_DIR not redirected'

sed -e "s#cursor()#cursor('$WORK/config')#g" \
    -e "s#from 'digest'#from '$SCRIPTS/testenv.uc'#" \
    -e "s#from 'ubus'#from '$SCRIPTS/testenv.uc'#" \
    -e "s#from 'homeproxy'#from '$SCRIPTS/testenv.uc'#" \
    -e "s#from 'parse_uri'#from '$SCRIPTS/testenv.uc'#" \
    -e "s#'/etc/init.d/homeproxy'#'$WORK/init'#" \
    "$ROOT/root/etc/homeproxy/scripts/update_subscriptions.uc" > "$SCRIPTS/update_subscriptions.uc"
chmod +x "$SCRIPTS/update_subscriptions.uc"
grep -q "'$WORK/init'" "$SCRIPTS/update_subscriptions.uc" || fail 'init script not redirected'

cat > "$WORK/init" <<SH
#!/bin/sh
echo "\$1" >> "$WORK/run/actions"
exit "\$(cat "$WORK/run/reload_rc" 2>/dev/null || echo 0)"
SH
chmod +x "$WORK/init"

cat > "$SCRIPTS/testenv.uc" <<'UC'
import { popen, readfile } from 'fs';
import { SUBSCRIPTION_STATUS as STATUS } from '__SCRIPTS__/homeproxy.uc';
export const SUBSCRIPTION_STATUS = STATUS;
export const RUN_DIR = '__WORK__/run';
export const DEFAULTS = { subscription: { filter_nodes: 'disabled', packet_encoding: 'xudp' } };
function shellQuote(s) { return "'" + replace(s, /'/g, "'\\''") + "'"; }
export function md5(s) {
	const p = popen('printf %s ' + shellQuote(s) + ' | md5sum', 'r');
	const hash = substr(p.read('all'), 0, 32);
	p.close();
	return hash;
};
export function getTime() { return 'test'; };
export function isEmpty(v) { return v == null || v === '' || length(v) === 0; };
export function connect() { return { call: () => ({ with_quic: true }) }; };
export function wGETVerbose(url, ua) {
	if (readfile(RUN_DIR + '/actions')) die('service reloaded before fetch');
	if (readfile(RUN_DIR + '/throw')) die('fetch exception');
	if (index(url, 'https://example.com/fail') === 0)
		return { content: null, error: 'wget exited with status 8: ' + url + ': ERROR 404' };
	return { content: readfile(RUN_DIR + '/response') };
};
export function decodeBase64Str(s) { return null; };
export function parse_uri(node, features, log) { return node; };
UC
sed -i -e "s#__WORK__#$WORK#g" -e "s#__SCRIPTS__#$SCRIPTS#g" "$SCRIPTS/testenv.uc"

fail_url='https://example.com/fail?token=secret'
# ids as the migration gives them (the md5 of the URL), see the end
sub_hash="$(printf %s 'https://example.com/sub' | md5sum | cut -c1-32)"
failed_hash="$(printf %s "$fail_url" | md5sum | cut -c1-32)"
cat > "$WORK/config/homeproxy" <<UCI
config homeproxy 'subscription'
config subscription_source '$sub_hash'
 option label 'name'
 option url 'https://example.com/sub'
config subscription_source '$failed_hash'
 option url '$fail_url'
config subscription_source 'nourl'
config node 'manual'
 option label 'Manual'
 option address 'manual.example'
config node 'orphan'
 option grouphash 'deleted-subscription'
 option label 'Orphan'
config routing_node 'single'
 option enabled '1'
 option node 'orphan'
config routing_node 'auto'
 option node 'urltest'
 list urltest_nodes 'all-nodes'
 list urltest_nodes 'orphan'
 list urltest_nodes 'sub_$sub_hash'
 list urltest_nodes 'sub_gone'
 list urltest_nodes 'sub_nourl'
config node 'nourl_node'
 option grouphash 'nourl'
 option label 'Kept without URL'
UCI
printf "\nconfig node 'failed'\n option grouphash '%s'\n option label 'Preserved on fetch failure'\n" "$failed_hash" >> "$WORK/config/homeproxy"

run_update() { ucode "$SCRIPTS/update_subscriptions.uc" "$@"; }
# check '<ucode expression on s (status) and u (uci cursor)>' '<label>'
check() {
	cat > "$WORK/check.uc" <<UC
import { cursor } from 'uci';
import { readfile } from 'fs';
import { readSubscriptionStatus } from '$SCRIPTS/homeproxy.uc';
import { md5 } from '$SCRIPTS/testenv.uc';
const s = readSubscriptionStatus(), u = cursor('$WORK/config');
const sub = s.subscriptions?.['$sub_hash'], failed = s.subscriptions?.['$failed_hash'];
if (!($1)) { warn(sprintf('status: %J\n', s)); exit(1); }
UC
	ucode "$WORK/check.uc" || fail "$2"
}

# A number and an empty value, as parse_uri may return them, are stored the
# way UCI keeps them, so the next run sees no change.
printf '%s' '[{"type":"trojan","label":"A","address":"example.com","port":443,"password":"one","tls_sni":null,"tls_alpn":[]}]' > "$WORK/run/response"
run_update run-1
check "s.id === 'run-1' && s.state === 'done' && s.added === 1 && s.removed === 1" 'first run summary'
check "length(s.subscriptions) === 2" 'a subscription without URL is left out'
check "sub.state === 'done' && sub.nodes === 1" 'per-subscription count'
check "failed.state === 'failed' && failed.error === 'fetch' && index(failed.detail, 'ERROR 404') >= 0" 'per-subscription failure'
! grep -q secret "$WORK/run/subscriptions.json" "$WORK/run/homeproxy.log" || fail 'subscription token leaked into status or log'
[ "$(cat "$WORK/run/actions")" = reload ] || fail 'a change must reload (not restart) the service once'
check "u.get('homeproxy', md5(md5('https://example.com/sub') + 'A'), 'port') === '443'" 'port stored as string'
cp "$WORK/config/homeproxy" "$WORK/first"
rm "$WORK/run/actions"
run_update
[ ! -e "$WORK/run/actions" ] || fail 'parser output in non-UCI form reported as a change'
cmp "$WORK/first" "$WORK/config/homeproxy" || fail 'unchanged update rewrote the config'
check "s.state === 'done' && !s.added && !s.updated && !s.removed" 'no-op summary'

# New fields and changed list options must reach an existing named node.
printf '%s' '[{"type":"trojan","label":"A","address":"example.com","port":"443","password":"two","tls":"1","tls_alpn":["h2","http/1.1"]}]' > "$WORK/run/response"
run_update
check "s.updated === 1 && !s.added && !s.removed" 'update counted'
check "(function() {
	const name = md5(md5('https://example.com/sub') + 'A');
	return u.get('homeproxy', name, 'password') === 'two' && u.get('homeproxy', name, 'tls') === '1' &&
		join(',', u.get('homeproxy', name, 'tls_alpn') || []) === 'h2,http/1.1';
})()" 'fresh fields lost'
check "!!u.get('homeproxy', 'failed')" 'failed subscription lost its old nodes'
check "!u.get('homeproxy', 'orphan') && !!u.get('homeproxy', 'manual')" 'wrong node deleted'
check "u.get('homeproxy', 'single', 'node') === 'orphan'" 'routing reference was silently reassigned'
check "join(',', u.get('homeproxy', 'auto', 'urltest_nodes') || []) === 'all-nodes,sub_$sub_hash,sub_nourl'" 'dangling group member'
check "!!u.get('homeproxy', 'nourl_node')" 'a subscription without URL lost its nodes'
cp "$WORK/config/homeproxy" "$WORK/before"
rm "$WORK/run/actions"

# Fetch failure and exceptions keep config and service intact, release the
# lock, and report failure.
: > "$WORK/run/response"
if run_update; then fail 'empty response succeeded'; fi
cmp "$WORK/before" "$WORK/config/homeproxy"
[ ! -e "$WORK/run/actions" ]
check "s.state === 'failed' && s.error === 'no_nodes' && sub.error === 'fetch'" 'all-failed summary'
echo 1 > "$WORK/run/throw"
if run_update; then fail 'exception succeeded'; fi
rm "$WORK/run/throw"
[ ! -e "$WORK/run/actions" ]
check "s.state === 'failed' && s.error === 'exception' && index(s.detail, 'fetch exception') >= 0" 'exception summary'

# A held lock is busy and leaves the status alone; the status of a run whose
# process died reads as interrupted.
cat > "$SCRIPTS/update_subscriptions_holder.uc" <<UC
import { open, readlink, writefile } from 'fs';
const f = open('$WORK/run/update_subscriptions.flock', 'a');
if (!f.lock('xn')) die('cannot hold lock');
writefile('$WORK/run/subscriptions.json', sprintf('%J', { id: 'held', state: 'running', pid: int(readlink('/proc/self')) }));
writefile('$WORK/ready', '1');
while (true) { }
UC
ucode "$SCRIPTS/update_subscriptions_holder.uc" &
holder=$!
trap 'kill "$holder" 2>/dev/null || true' EXIT
wait_ready() { for attempt in 1 2 3 4 5; do [ -f "$WORK/ready" ] && return 0; sleep 1; done; fail 'lock holder did not start'; }
wait_ready
cp "$WORK/run/subscriptions.json" "$WORK/held"
rc=0
run_update || rc=$?
[ "$rc" -eq 2 ] || fail "busy lock gave $rc"
cmp "$WORK/held" "$WORK/run/subscriptions.json" || fail 'a refused run touched the status'
check "s.id === 'held' && s.state === 'running'" 'a live run reads as running'
kill -9 "$holder"
wait "$holder" 2>/dev/null || true
trap - EXIT
check "s.id === 'held' && s.state === 'failed' && s.error === 'interrupted'" 'a dead run reads as interrupted'

# A failed reload is reported, the nodes stay saved.
printf '%s' '[{"type":"trojan","label":"B","address":"example.com","port":"443","password":"two"}]' > "$WORK/run/response"
echo 1 > "$WORK/run/reload_rc"
run_update
rm "$WORK/run/reload_rc" "$WORK/run/actions"
check "s.state === 'done' && s.reload_failed === true && s.added === 1 && s.removed === 1" 'reload failure reported'

# A new URL of the same subscription keeps its nodes and the groups picking it.
cat > "$WORK/move.uc" <<UC
import { cursor } from 'uci';
const u = cursor('$WORK/config');
u.set('homeproxy', '$sub_hash', 'url', 'https://example.com/moved?token=new');
u.commit('homeproxy');
UC
ucode "$WORK/move.uc"
cp "$WORK/config/homeproxy" "$WORK/moved"
run_update
check "s.state === 'done' && !s.added && !s.removed && sub.nodes === 1" 'a moved subscription is the same one'
check "!!u.get('homeproxy', md5('$sub_hash' + 'B'))" 'the node of a moved subscription kept its name'
check "index(u.get('homeproxy', 'auto', 'urltest_nodes'), 'sub_$sub_hash') >= 0" 'the group kept the moved subscription'
cmp "$WORK/moved" "$WORK/config/homeproxy" || fail 'a moved subscription changed the config'

# Deleting all nodes must not prevent repopulating from the subscription.
cat > "$WORK/clear.uc" <<UC
import { cursor } from 'uci';
const u = cursor('$WORK/config');
const names = [];
u.foreach('homeproxy', 'node', (n) => push(names, n['.name']));
for (let name in names) u.delete('homeproxy', name);
u.commit('homeproxy');
UC
ucode "$WORK/clear.uc"
run_update
grep -q "option label 'B'" "$WORK/config/homeproxy" || fail 'nodes not repopulated'
rm "$WORK/run/actions"

# rpcd: the update starts in the background and is followed by its id; a
# running update is reported instead of starting another one.
sed -e "s#^const HP_DIR = '/etc/homeproxy';#const HP_DIR = '$WORK/hp';#" \
    -e "s#^const RUN_DIR = '/var/run/homeproxy';#const RUN_DIR = '$WORK/run';#" \
    -e "s#'/etc/homeproxy/scripts/homeproxy.uc'#'$SCRIPTS/homeproxy.uc'#" \
    -e "s#^return { 'luci.homeproxy': methods };##" \
    "$ROOT/root/usr/share/rpcd/ucode/luci.homeproxy" > "$WORK/rpcd.uc"
cat >> "$WORK/rpcd.uc" <<'UC'
function call(method) { return methods[method].call({ args: {} }); }
const t0 = time();
const r = call('subscription_update');
if (!r.id || r.running || time() - t0 > 2) die(sprintf('start: %J', r));
let s;
for (let i = 0; i < 20; i++) {
	s = call('subscription_status');
	if (s.id === r.id && s.state !== 'running')
		break;
	system('sleep 1');
}
if (s.id !== r.id || s.state !== 'done') die(sprintf('status: %J', s));
print('ok\n');
UC
[ "$(ucode "$WORK/rpcd.uc")" = ok ] || fail 'rpcd background update'

rm -f "$WORK/ready"
ucode "$SCRIPTS/update_subscriptions_holder.uc" &
holder=$!
trap 'kill "$holder" 2>/dev/null || true' EXIT
wait_ready
cat > "$WORK/rpcd-busy.uc" <<'UC'
const r = methods.subscription_update.call({ args: {} });
if (r.id !== 'held' || !r.running) die(sprintf('busy: %J', r));
print('ok\n');
UC
sed -e '/^function call(method)/,$d' "$WORK/rpcd.uc" > "$WORK/rpcd-base.uc"
cat "$WORK/rpcd-busy.uc" >> "$WORK/rpcd-base.uc"
[ "$(ucode "$WORK/rpcd-base.uc")" = ok ] || fail 'rpcd started a second update'
kill -9 "$holder"
wait "$holder" 2>/dev/null || true
trap - EXIT

# Migration: the old list of URLs becomes one section per subscription, named
# by the md5 of its URL: the grouphash its nodes and groups already use.
mkdir -p "$WORK/legacy"
cat > "$WORK/legacy/homeproxy" <<UCI
config homeproxy 'migration'
 option crontab '1'
config homeproxy 'subscription'
 option auto_update '0'
 list subscription_url 'https://example.com/sub#My%20Sub'
 list subscription_url 'https://example.com/sub#again'
 list subscription_url '$fail_url'
UCI
sed -e "s#cursor()#cursor('$WORK/legacy')#" \
    -e "s#from 'homeproxy'#from '$SCRIPTS/homeproxy.uc'#" \
    "$ROOT/root/etc/homeproxy/scripts/migrate_config.uc" > "$SCRIPTS/migrate_config.uc"
grep -q "cursor('$WORK/legacy')" "$SCRIPTS/migrate_config.uc" || fail 'migration cursor not redirected'
ucode "$SCRIPTS/migrate_config.uc"
cat > "$WORK/check-migration.uc" <<UC
import { cursor } from 'uci';
const u = cursor('$WORK/legacy');
const ids = [];
u.foreach('homeproxy', 'subscription_source', (s) => push(ids, s['.name']));
if (join(',', ids) !== '$sub_hash,$failed_hash') die(sprintf('ids: %J', ids));
if (u.get('homeproxy', '$sub_hash', 'url') !== 'https://example.com/sub') die('url keeps the fragment');
if (u.get('homeproxy', '$sub_hash', 'label') !== 'My Sub') die('label not taken from the fragment');
if (u.get('homeproxy', '$failed_hash', 'url') !== '$fail_url' || u.get('homeproxy', '$failed_hash', 'label')) die('second subscription');
if (u.get('homeproxy', 'subscription', 'subscription_url')) die('the list is left behind');
if (u.get('homeproxy', 'subscription', 'auto_update') !== '0') die('other settings lost');
UC
ucode "$WORK/check-migration.uc" || fail 'migration'
cp "$WORK/legacy/homeproxy" "$WORK/migrated"
ucode "$SCRIPTS/migrate_config.uc"
cmp "$WORK/migrated" "$WORK/legacy/homeproxy" || fail 'migrating again changed the config'

echo 'PASS: subscription lifecycle, status reporting, stable ids across URL changes, migration, field updates, failure preservation, no-op update, process lock and background start'
