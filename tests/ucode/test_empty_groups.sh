#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
ROOT="$(cd "${1:-.}" && pwd)"
WORK="${2:-/tmp/hp-empty-groups-test}"
mkdir -p "$WORK"
cat > "$WORK/check.uc" <<'UC'
'use strict';
import { build } from 'client.outbounds';
const groups = [
	{ '.name': 'single', enabled: '1', node: 'gone' },
	{ '.name': 'auto', enabled: '1', node: 'urltest', urltest_nodes: ['sub_deleted'] },
	{ '.name': 'pick', enabled: '1', node: 'selector', selector_nodes: ['gone'] }
];
const ctx = {
	uci: {
		foreach: (config, type, cb) => { if (type === 'routing_node') map(groups, cb); },
		get: () => null,
		get_all: () => null
	},
	node_tag: (name) => name,
	self_mark: '100'
};
const result = build(ctx);
if (filter(result.outbounds, (o) => o.tag === 'gone' && o.type === 'block')[0] == null)
	die('removed single node must block traffic with its original tag');
for (let tag in ['auto', 'pick']) {
	const group = filter(result.outbounds, (o) => o.tag === tag)[0];
	if (group.type !== 'selector' || join(',', group.outbounds) !== 'block-out')
		die('empty group must retain its tag and block traffic');
}
print(sprintf('%J', { outbounds: result.outbounds }));
UC
ucode -L "$ROOT/root/etc/homeproxy/scripts" "$WORK/check.uc" > "$WORK/config.json"
sing-box check -c "$WORK/config.json"
sing-box run -c "$WORK/config.json" > "$WORK/service.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
sleep 1
kill -0 "$pid"
kill "$pid"
wait "$pid"
trap - EXIT
echo 'PASS: empty URLTest/Selector retain tags and sing-box starts with blocked groups'
