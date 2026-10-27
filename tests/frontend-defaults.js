#!/usr/bin/env node
// SPDX-License-Identifier: GPL-2.0-only
//
// A form default must match the fallback the backend applies when the option
// is missing (DEFAULTS in homeproxy.uc), or the page shows one value while
// the service runs with another. Reads the form snapshots, which
// luci-form-snapshot.js keeps equal to the live forms.

'use strict';

const fs = require('fs');
const path = require('path');

const root = process.argv[2] || path.join(__dirname, '..');
const src = fs.readFileSync(path.join(root, 'root/etc/homeproxy/scripts/homeproxy.uc'), 'utf8');
const literal = src.match(/^export const DEFAULTS = (\{[\s\S]*?\n\});$/m);
if (!literal)
	throw new Error('DEFAULTS not found in homeproxy.uc');
const DEFAULTS = new Function(`return ${literal[1]};`)();

/* "<section>.<option>" -> form defaults; a SectionValue names its section */
const forms = {};
function walk(section, name) {
	for (const o of section.options) {
		if (o.subsection)
			walk(o.subsection, o.subsection.name.replace(/^_/, ''));
		if (o.props.default !== undefined)
			(forms[`${name}.${o.name}`] = forms[`${name}.${o.name}`] || []).push(o.props.default);
	}
}
for (const view of [ 'client', 'node', 'server' ]) {
	const snapshot = JSON.parse(fs.readFileSync(path.join(root, 'tests/snapshots', view + '.json'), 'utf8'));
	for (const section of snapshot.sections)
		walk(section, section.name);
}

let checks = 0, failed = 0;
for (const section in DEFAULTS)
	for (const option in DEFAULTS[section]) {
		const key = `${section}.${option}`;
		for (const value of forms[key] || []) {
			checks++;
			if (value !== DEFAULTS[section][option]) {
				failed++;
				console.log(`FAIL: the form default of ${key} is ${JSON.stringify(value)}, DEFAULTS has ${JSON.stringify(DEFAULTS[section][option])}`);
			}
		}
	}

console.log(`${checks} form defaults checked against DEFAULTS, ${failed} failures`);
process.exit(failed || !checks ? 1 : 0);
