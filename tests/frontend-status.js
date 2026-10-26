#!/usr/bin/env node
// SPDX-License-Identifier: GPL-2.0-only
//
// hp.getServiceStatus() / hp.renderStatus(): a failed `service list` call
// (rpcd busy restarting, expired session) must show STATUS UNKNOWN, not
// NOT RUNNING.

'use strict';

const path = require('path');
const { loadLuciModule } = require('./luci-form-snapshot.js');

const root = process.argv[2] || path.join(__dirname, '..');
const file = path.join(root, 'htdocs/luci-static/resources/homeproxy.js');

/* an rpc whose `service list` call answers with `reply`, or rejects when it is an Error */
function loadWith(reply) {
	const rpc = {
		declare: (spec) => (...args) => {
			if (spec.object !== 'service' || spec.method !== 'list' || args[0] !== 'homeproxy')
				return Promise.reject(new Error(`unexpected call ${spec.object}.${spec.method}(${args})`));
			return (reply instanceof Error) ? Promise.reject(reply) : Promise.resolve(reply);
		}
	};
	return loadLuciModule(file, { rpc });
}

const instances = (running) => ({ homeproxy: { instances: { 'sing-box-c': { running } } } });

const cases = [
	[ 'running instance', instances(true), 'sing-box-c', true ],
	[ 'stopped instance', instances(false), 'sing-box-c', false ],
	[ 'instance of the other side', instances(true), 'sing-box-s', false ],
	[ 'service not registered', {}, 'sing-box-c', false ],
	[ 'rpcd error', new Error('XHR request timed out'), 'sing-box-c', null ]
];

const renders = [
	[ true, 'green', 'RUNNING' ],
	[ false, 'red', 'NOT RUNNING' ],
	[ null, '#d08000', 'STATUS UNKNOWN' ],
	[ undefined, '#d08000', 'STATUS UNKNOWN' ]
];

(async () => {
	let failed = 0;
	const check = (ok, label) => {
		if (!ok)
			failed++;
		console.log(`${ok ? 'PASS' : 'FAIL'}: ${label}`);
	};

	for (const [ label, reply, instance, want ] of cases) {
		const got = await loadWith(reply).getServiceStatus(instance);
		check(got === want, `${label} -> ${JSON.stringify(got)}`);
	}

	const hp = loadWith({});
	for (const [ running, color, state ] of renders) {
		const html = hp.renderStatus('HomeProxy NEXT', '1.14.4', running);
		check(html.includes(`color:${color}`) && html.includes(`(sing-box v1.14.4) ${state}<`),
			`render ${JSON.stringify(running)} -> ${state}`);
	}

	console.log(`${cases.length + renders.length} checks, ${failed} failures`);
	process.exit(failed ? 1 : 0);
})();
