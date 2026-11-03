#!/usr/bin/env node
// SPDX-License-Identifier: GPL-2.0-only
'use strict';
const assert = require('assert');
const path = require('path');
const crypto = require('crypto');
const { loadLuciModule } = require('./luci-form-snapshot.js');
const root = process.argv[2] || path.join(__dirname, '..');
const hash = s => crypto.createHash('md5').update(s).digest('hex');

let nodes = {}, routing = {}, urls = [], changes = {}, sets = [];
const rpcHandlers = {};
const calls = [];
const uci = {
	sections: (_c, type, fn) => Object.values(type === 'node' ? nodes : routing).forEach(fn),
	remove: (_c, id) => { delete nodes[id]; },
	set: (_c, id, key, value) => { sets.push(id); routing[id][key] = value; },
	get: (_c, sid, opt) => (sid === 'subscription' && opt === 'subscription_url') ? urls : undefined,
	changes: () => Promise.resolve(changes)
};
const rpc = {
	declare: (opts) => (...args) => {
		calls.push(opts.method);
		return rpcHandlers[opts.method](...args);
	}
};
let notifications = [], modal = null, reloads = 0, rendered = null;
const ui = {
	showModal: (_title, body) => { modal = body; },
	hideModal: () => { modal = null; },
	addNotification: (_title, body) => notifications.push(body)
};
const dom = { content: (_el, node) => { rendered = node; } };
const mod = loadLuciModule(path.join(root, 'htdocs/luci-static/resources/view/homeproxy/node.js'), {
	uci, rpc, ui, dom, homeproxy: { calcStringMD5: hash }
});
mod.pollInterval = 0;
global.location = { reload: () => { reloads++; } };
const map = { save: () => Promise.resolve() };
/* E(tag, children) as well as E(tag, attrs, children) */
const text = (node) => (node == null) ? '' : (typeof node !== 'object') ? String(node) :
	Array.isArray(node) ? node.map(text).join('') :
	text((Array.isArray(node.attrs) || typeof node.attrs === 'string') ? node.attrs : null) + text(node.children);

function reset(statuses) {
	notifications = []; modal = null; reloads = 0; rendered = null; calls.length = 0;
	let i = 0;
	rpcHandlers.subscription_status = () => {
		const s = statuses[Math.min(i++, statuses.length - 1)];
		return (s instanceof Error) ? Promise.reject(s) : Promise.resolve(s);
	};
	rpcHandlers.subscription_update = () => Promise.resolve({ id: 'run1' });
	rpcHandlers.commit = () => Promise.resolve();
}

(async () => {
	/* removing or replacing subscriptions */
	const url = 'https://example.com/new';
	nodes = {
		manual: { '.name': 'manual' },
		old: { '.name': 'old', grouphash: hash('https://example.com/old') },
		fresh: { '.name': 'fresh', grouphash: hash(url) }
	};
	routing = {
		single: { '.name': 'single', enabled: '1', node: 'old' },
		group: { '.name': 'group', selector_nodes: ['old', 'manual', 'all-nodes', 'sub_' + hash(url), 'sub_deleted'] },
		untouched: { '.name': 'untouched', urltest_nodes: ['manual'] }
	};
	assert.equal(mod.removeSubscriptionNodes([url + '#renamed']), 1);
	assert.deepStrictEqual(Object.keys(nodes), ['manual', 'fresh']);
	assert.equal(routing.single.enabled, '1', 'preserve routing references for the generator to block safely');
	assert.deepStrictEqual(routing.group.selector_nodes, ['manual', 'all-nodes', 'sub_' + hash(url)]);
	assert.ok(!sets.includes('untouched'), 'an unchanged group list is not rewritten');
	/* "remove all nodes" keeps the configured subscriptions in the groups */
	assert.equal(mod.removeSubscriptionNodes([url], true), 1);
	assert.deepStrictEqual(Object.keys(nodes), ['manual']);
	assert.deepStrictEqual(routing.group.selector_nodes, ['manual', 'all-nodes', 'sub_' + hash(url)]);
	mod.removeSubscriptionNodes([]);
	assert.deepStrictEqual(routing.group.selector_nodes, ['manual', 'all-nodes']);

	urls = [url + '#My%20sub'];
	const h = hash(url);
	const running = (stage, sub) => ({ id: 'run1', state: 'running', stage, subscriptions: { [h]: sub } });
	const done = (sub, extra) => Object.assign({ id: 'run1', state: 'done', finished: 1, added: 2, updated: 0, removed: 0,
		subscriptions: { [h]: sub } }, extra);

	/* pending changes are committed first, progress is shown, success reloads */
	changes = { homeproxy: [['set']] };
	reset([
		{ id: 'previous', state: 'done' },
		running('fetching', { state: 'fetching' }),
		running('reloading', { state: 'done', nodes: 2 }),
		done({ state: 'done', nodes: 2 })
	]);
	await mod.updateSubscriptions(map);
	assert.deepStrictEqual(calls.slice(0, 2), ['commit', 'subscription_update']);
	assert.equal(reloads, 1, 'a clean update reloads the page');
	assert.equal(notifications.length, 0);
	assert.ok(text(rendered).includes('My sub'), 'subscriptions are shown by their name');

	/* nothing pending: no commit */
	changes = {};
	reset([done({ state: 'done', nodes: 2 })]);
	await mod.updateSubscriptions(map);
	assert.ok(!calls.includes('commit'));
	assert.equal(reloads, 1);

	/* a failed subscription keeps the dialog open with the reason */
	reset([done({ state: 'failed', error: 'fetch', detail: 'wget exited with status 4' }, { added: 0 })]);
	await mod.updateSubscriptions(map);
	assert.equal(reloads, 0, 'a partial failure is shown, not reloaded away');
	assert.ok(modal, 'the dialog stays open');
	assert.ok(text(rendered).includes('wget exited with status 4'));

	/* a reload failure is reported as well */
	reset([done({ state: 'done', nodes: 2 }, { reload_failed: true })]);
	await mod.updateSubscriptions(map);
	assert.equal(reloads, 0);
	assert.ok(text(rendered).includes('failed to reload'));

	/* an update that was already running (auto update) is followed */
	reset([Object.assign(running('fetching', { state: 'fetching' }), { id: 'cron' }), done({ state: 'done', nodes: 1 }, { id: 'cron' })]);
	rpcHandlers.subscription_update = () => Promise.resolve({ id: 'cron', running: true });
	await mod.updateSubscriptions(map);
	assert.equal(reloads, 1);
	/* ... also when it took the lock right after the start */
	reset([{ id: 'cron', state: 'running', subscriptions: {} }, done({ state: 'done', nodes: 1 }, { id: 'cron' })]);
	await mod.updateSubscriptions(map);
	assert.equal(reloads, 1);

	/* transient RPC errors while the service reloads are retried */
	reset([new Error('XHR timeout'), new Error('XHR timeout'), done({ state: 'done', nodes: 1 })]);
	await mod.updateSubscriptions(map);
	assert.equal(reloads, 1);
	assert.equal(notifications.length, 0);

	/* failures that end the dialog with a notification */
	reset([new Error('XHR timeout')]);
	await mod.updateSubscriptions(map);
	assert.equal(notifications.length, 1, 'persistent RPC failure');
	assert.equal(modal, null);

	reset([{ id: 'previous', state: 'done' }]);
	const now = Date.now;
	let clock = 0;
	Date.now = () => (clock += 4000);
	await mod.updateSubscriptions(map);
	Date.now = now;
	assert.equal(notifications.length, 1, 'an update that never shows up');
	assert.ok(text(notifications[0]).includes('did not start'));

	reset([]);
	rpcHandlers.subscription_update = () => Promise.resolve({ error: 'failed to start the update' });
	await mod.updateSubscriptions(map);
	assert.ok(text(notifications[0]).includes('failed to start'));

	reset([]);
	await mod.updateSubscriptions({ save: () => Promise.reject(new Error('invalid field')) });
	assert.ok(text(notifications[0]).includes('invalid field'), 'a form that does not save starts nothing');
	assert.ok(!calls.includes('subscription_update'));

	urls = [];
	reset([]);
	await mod.updateSubscriptions(map);
	assert.ok(text(notifications[0]).includes('no subscription URL'));
	assert.ok(!calls.includes('subscription_update'));

	assert.equal(reloads, 0);
	delete global.location;
	console.log('PASS: subscription removal cleans references; updates commit first, follow the background run and report every outcome');
})().catch(err => { console.error(err); process.exit(1); });
