#!/usr/bin/env node
// SPDX-License-Identifier: GPL-2.0-only
//
// view/homeproxy/plugins.js: the status column compares the plugin files
// with the last run of the generators (plugins-<client|server>.json), so a
// change made over SSH or on the page shows up as "not applied yet".

'use strict';

const path = require('path');
const { loadLuciModule } = require('./luci-form-snapshot.js');

const root = process.argv[2] || path.join(__dirname, '..');
const page = loadLuciModule(path.join(root, 'htdocs/luci-static/resources/view/homeproxy/plugins.js'), {});

const on = (name, mtime) => ({ name, file: name + '.uc', enabled: true, mtime });
const off = (name, mtime) => ({ name, file: name + '.uc.disabled', enabled: false, mtime });
const run = (plugins, extra) => Object.assign({ time: 1, plugins }, extra);

const cases = [
	[ 'never applied', on('a', 5), {}, true, /Not applied yet/ ],
	[ 'applied on the client', on('a', 5), { client: run({ a: { status: 'applied', mtime: 5 } }) }, false, /Active on the client/ ],
	[ 'edited since the run', on('a', 6), { client: run({ a: { status: 'applied', mtime: 5 } }) }, true, /Changed, not applied yet/ ],
	[ 'added after the run', on('b', 5), { client: run({ a: { status: 'applied', mtime: 5 } }) }, true, /Not applied yet/ ],
	[ 'failed', on('a', 5), { client: run({ a: { status: 'error', error: 'boom', mtime: 5 } }) }, false, /Error on the client: boom/ ],
	[ 'rolled back by the check', on('a', 5), { client: run({ a: { status: 'applied', mtime: 5 } }, { fallback: true }) }, false, /Rolled back on the client/ ],
	[ 'server only', on('a', 5), {
		client: run({ a: { status: 'unused', mtime: 5 } }),
		server: run({ a: { status: 'applied', mtime: 5 } })
	}, false, /^Active on the server$/ ],
	[ 'no hook at all', on('a', 5), { client: run({ a: { status: 'unused', mtime: 5 } }) }, false, /No client\(\) or server\(\) function/ ],
	[ 'disabled, never ran', off('a', 5), { client: run({}) }, false, /^Disabled$/ ],
	[ 'disabled after it ran', off('a', 5), { client: run({ a: { status: 'applied', mtime: 5 } }) }, true, /still active until applied/ ]
];

let failed = 0, checks = 0;
for (const [ label, plugin, status, pending, text ] of cases) {
	const got = page.pluginState(plugin, status);
	const ok = got.pending === pending && text.test(got.text);
	checks++;
	if (!ok)
		failed++;
	console.log(`${ok ? 'PASS' : 'FAIL'}: ${label}${ok ? '' : ` (got ${JSON.stringify(got)})`}`);
}

const removed = [
	[ 'a deleted plugin that was active', [], { client: run({ a: { status: 'applied', mtime: 5 } }) }, true ],
	[ 'a deleted plugin that had failed', [], { client: run({ a: { status: 'error', mtime: 5 } }) }, false ],
	[ 'nothing deleted', [ on('a', 5) ], { client: run({ a: { status: 'applied', mtime: 5 } }) }, false ]
];
for (const [ label, plugins, status, want ] of removed) {
	const got = page.removedSinceRun(plugins, status);
	checks++;
	if (got !== want)
		failed++;
	console.log(`${got === want ? 'PASS' : 'FAIL'}: ${label}`);
}

console.log(`${checks} checks, ${failed} failures`);
process.exit(failed ? 1 : 0);
