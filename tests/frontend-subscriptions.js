#!/usr/bin/env node
// SPDX-License-Identifier: GPL-2.0-only
'use strict';
const assert = require('assert');
const path = require('path');
const crypto = require('crypto');
const { loadLuciModule } = require('./luci-form-snapshot.js');
const root = process.argv[2] || path.join(__dirname, '..');
const hash = s => crypto.createHash('md5').update(s).digest('hex');
let nodes = {}, routing = {}, code = 0, reloads = 0, notifications = [], modals = 0;
const uci = {
	sections: (_c, type, fn) => Object.values(type === 'node' ? nodes : routing).forEach(fn),
	remove: (_c, id) => { delete nodes[id]; },
	set: (_c, id, key, value) => { routing[id][key] = value; }
};
const mod = loadLuciModule(path.join(root, 'htdocs/luci-static/resources/view/homeproxy/node.js'), {
	uci, homeproxy: { calcStringMD5: hash },
	fs: { exec: () => code instanceof Error ? Promise.reject(code) : Promise.resolve({ code }) },
	ui: {
		showModal: () => { modals++; }, hideModal: () => { modals--; },
		addNotification: (_title, body) => notifications.push(body)
	}
});
global.location = { reload: () => { reloads++; } };
(async () => {
	const url = 'https://example.com/new';
	nodes = {
		manual: { '.name': 'manual' },
		old: { '.name': 'old', grouphash: hash('https://example.com/old') },
		fresh: { '.name': 'fresh', grouphash: hash(url) }
	};
	routing = {
		single: { '.name': 'single', enabled: '1', node: 'old' },
		group: { '.name': 'group', selector_nodes: ['old', 'manual', 'all-nodes', 'sub_' + hash(url), 'sub_deleted'] }
	};
	mod.removeSubscriptionNodes([url + '#renamed']);
	assert.deepStrictEqual(Object.keys(nodes), ['manual', 'fresh']);
	assert.equal(routing.single.enabled, '1', 'preserve routing references for the generator to block safely');
	assert.deepStrictEqual(routing.group.selector_nodes, ['manual', 'all-nodes', 'sub_' + hash(url)]);
	mod.removeSubscriptionNodes([]);
	assert.deepStrictEqual(Object.keys(nodes), ['manual']);
	for (const result of [2, 1, new Error('RPC timeout'), 0]) {
		code = result;
		await mod.updateSubscriptions();
		assert.equal(modals, 0, 'busy dialog must close on every outcome');
	}
	assert.equal(notifications.length, 3, 'busy, update failure and RPC failure must be visible');
	assert.equal(reloads, 1, 'only success reloads the page');
	delete global.location;
	console.log('PASS: deleting/replacing subscriptions preserves manual nodes, cleans references and displays update outcomes');
})().catch(err => { console.error(err); process.exit(1); });
