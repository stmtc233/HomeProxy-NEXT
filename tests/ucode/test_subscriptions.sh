#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Exercise the production updater with real UCI/files/locks and deterministic
# network, parser and service boundaries. Protocol parsing has its own suite.
set -eu
ROOT="$(cd "${1:-.}" && pwd)"
WORK="${2:-/tmp/hp-subscriptions-test}"
rm -rf "$WORK"
mkdir -p "$WORK/config" "$WORK/run" "$WORK/scripts"
sed -e "s#const uci = cursor();#const uci = cursor('$WORK/config');#" \
    -e "s#from 'digest'#from 'testenv'#" \
    -e "s#from 'ubus'#from 'testenv'#" \
    -e "s#from 'luci.sys'#from 'testenv'#" \
    -e "s#from 'homeproxy'#from 'testenv'#" \
    -e "s#from 'parse_uri'#from 'testenv'#" \
    "$ROOT/root/etc/homeproxy/scripts/update_subscriptions.uc" > "$WORK/scripts/update.uc"
cat > "$WORK/scripts/testenv.uc" <<'UC'
import { open, popen, readfile } from 'fs';
export const RUN_DIR = '__WORK__/run';
export const HP_DIR = '__WORK__';
export const DEFAULTS = { subscription: { filter_nodes: 'disabled', packet_encoding: 'xudp' } };
export function shellQuote(s) { return "'" + replace(s, /'/g, "'\\''") + "'"; };
export function md5(s) {
	const p = popen('printf %s ' + shellQuote(s) + ' | md5sum', 'r');
	const hash = substr(p.read('all'), 0, 32);
	p.close();
	return hash;
};
export function getTime() { return 'test'; };
export function isEmpty(v) { return v == null || v === '' || length(v) === 0; };
export function connect() { return { call: () => ({ with_quic: true }) }; };
export function init_action(name, action) {
	const f = open(RUN_DIR + '/actions', 'a'); f.write(action + '\n'); f.close();
};
export function wGETVerbose(url, ua) {
	if (readfile(RUN_DIR + '/actions')) die('service stopped before fetch');
	if (readfile(RUN_DIR + '/throw')) die('fetch exception');
	if (url === 'https://example.com/fail') return { content: null };
	return { content: readfile(RUN_DIR + '/response') };
};
export function decodeBase64Str(s) { return null; };
export function parse_uri(node, features, log) { return node; };
UC
sed -i "s#__WORK__#$WORK#g" "$WORK/scripts/testenv.uc"
cat > "$WORK/config/homeproxy" <<'UCI'
config homeproxy 'subscription'
 list subscription_url 'https://example.com/sub#name'
 list subscription_url 'https://example.com/fail'
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
UCI
failed_hash="$(printf %s 'https://example.com/fail' | md5sum | cut -c1-32)"
printf "\nconfig node 'failed'\n option grouphash '%s'\n option label 'Preserved on fetch failure'\n" "$failed_hash" >> "$WORK/config/homeproxy"
printf '%s' '[{"type":"trojan","label":"A","address":"example.com","port":"443","password":"one"}]' > "$WORK/run/response"
run_update() { (cd "$WORK/scripts" && ucode update.uc); }
run_update
# New fields and changed list options must reach an existing named node.
printf '%s' '[{"type":"trojan","label":"A","address":"example.com","port":"443","password":"two","tls":"1","tls_alpn":["h2","http/1.1"]}]' > "$WORK/run/response"
rm "$WORK/run/actions"
run_update
cat > "$WORK/scripts/check.uc" <<'UC'
import { cursor } from 'uci';
import { md5 } from 'testenv';
const u = cursor('__WORK__/config');
const name = md5(md5('https://example.com/sub') + 'A');
if (u.get('homeproxy', name, 'password') !== 'two' || u.get('homeproxy', name, 'tls') !== '1') die('fresh fields lost');
if (join(',', u.get('homeproxy', name, 'tls_alpn') || []) !== 'h2,http/1.1') die('list fields lost');
if (!u.get('homeproxy', 'failed')) die('failed subscription lost its old nodes');
if (u.get('homeproxy', 'orphan') || !u.get('homeproxy', 'manual')) die('wrong node deleted');
if (u.get('homeproxy', 'single', 'node') !== 'orphan') die('routing reference was silently reassigned');
if (join(',', u.get('homeproxy', 'auto', 'urltest_nodes') || []) !== 'all-nodes') die('dangling group member');
UC
sed -i "s#__WORK__#$WORK#g" "$WORK/scripts/check.uc"
(cd "$WORK/scripts" && ucode check.uc)
cp "$WORK/config/homeproxy" "$WORK/before"
rm "$WORK/run/actions"
run_update
[ ! -e "$WORK/run/actions" ] || { echo 'FAIL: unchanged update restarted service'; exit 1; }
# Fetch failure and exceptions keep config and service intact, release the lock,
# and report nonzero to the frontend.
: > "$WORK/run/response"
if run_update; then echo 'FAIL: empty response succeeded'; exit 1; fi
cmp "$WORK/before" "$WORK/config/homeproxy"
[ ! -e "$WORK/run/actions" ]
touch "$WORK/run/throw"
if run_update; then echo 'FAIL: exception succeeded'; exit 1; fi
rm "$WORK/run/throw"
[ ! -e "$WORK/run/actions" ]
# A held lock is busy, but a process killed while holding it releases it.
cat > "$WORK/holder.uc" <<'UC'
import { open, writefile } from 'fs';
const f = open('__WORK__/run/update_subscriptions.flock', 'a');
if (!f.lock('xn')) die('cannot hold lock');
writefile('__WORK__/ready', '1');
while (true) { }
UC
sed -i "s#__WORK__#$WORK#g" "$WORK/holder.uc"
ucode "$WORK/holder.uc" &
holder=$!
trap 'kill "$holder" 2>/dev/null || true' EXIT
for attempt in 1 2 3 4 5; do [ -f "$WORK/ready" ] && break; sleep 1; done
rc=0
run_update || rc=$?
[ "$rc" -eq 2 ]
kill -9 "$holder"
wait "$holder" 2>/dev/null || true
trap - EXIT
printf '%s' '[{"type":"trojan","label":"A","address":"example.com","port":"443","password":"two","tls":"1","tls_alpn":["h2","http/1.1"]}]' > "$WORK/run/response"
run_update
[ ! -e "$WORK/run/actions" ]
# Deleting all nodes must not prevent repopulating from the subscription.
cat > "$WORK/scripts/clear.uc" <<'UC'
import { cursor } from 'uci';
const u = cursor('__WORK__/config');
const names = [];
u.foreach('homeproxy', 'node', (n) => push(names, n['.name']));
for (let name in names) u.delete('homeproxy', name);
u.commit('homeproxy');
UC
sed -i "s#__WORK__#$WORK#g" "$WORK/scripts/clear.uc"
(cd "$WORK/scripts" && ucode clear.uc)
run_update
grep -q "option password 'two'" "$WORK/config/homeproxy"
echo 'PASS: subscription lifecycle, field updates, failure preservation, no-op update and process lock'
