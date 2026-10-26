#!/usr/bin/env node
// SPDX-License-Identifier: GPL-2.0-only
//
// hp.calcStringMD5() must agree with a real MD5 over the UTF-8 bytes: the
// frontend hashes subscription URLs into sub_<hash> urltest entries and
// update_subscriptions.uc drops every entry whose hash matches no URL.

'use strict';

const crypto = require('crypto');
const path = require('path');
const { loadLuciModule } = require('./luci-form-snapshot.js');

const root = process.argv[2] || path.join(__dirname, '..');
const hp = loadLuciModule(path.join(root, 'htdocs/luci-static/resources/homeproxy.js'), {});

const inputs = [
	'', 'a', 'abc', 'message digest', 'abcdefghijklmnopqrstuvwxyz',
	'12345678901234567890123456789012345678901234567890123456789012345678901234567890',
	'x'.repeat(55), 'x'.repeat(56), 'x'.repeat(63), 'x'.repeat(64), 'x'.repeat(1000),
	'https://example.com/sub?token=abc123&flag=clash',
	'https://例子.com/订阅', 'café', '香港 01',
	'🇭🇰 香港 01', '🚀 自动选择', '👨‍👩‍👧 family', 'https://example.com/🙂/sub'
];

let failed = 0;
for (const input of inputs) {
	const got = hp.calcStringMD5(input);
	const want = crypto.createHash('md5').update(input, 'utf8').digest('hex');
	if (got !== want) {
		failed++;
		console.log(`FAIL: md5(${JSON.stringify(input)}) = ${got}, expected ${want}`);
	}
}

console.log(`${inputs.length} checks, ${failed} failures`);
process.exit(failed ? 1 : 0);
