#!/usr/bin/env node
// SPDX-License-Identifier: GPL-2.0-only
//
// homeproxy/client/common.js: the section-backed selects of the client tabs
// list the fixed choices first, then the enabled sections, and show a stored
// value as its label in the grid; the rule grids show one routing mode at a
// time, and rule labels only need to be unique within their mode.

'use strict';

const path = require('path');
const { loadLuciModule } = require('./luci-form-snapshot.js');

const root = process.argv[2] || path.join(__dirname, '..');
const file = path.join(root, 'htdocs/luci-static/resources/homeproxy/client/common.js');

const sections = {
	routing_node: [
		{ '.name': 'rn1', label: 'HK', enabled: '1' },
		{ '.name': 'rn2', enabled: '1' },
		{ '.name': 'rn3', label: 'off', enabled: '0' },
		{ '.name': 'toString', label: 'odd name', enabled: '1' }
	],
	dns_server: [
		{ '.name': 'ds1', label: 'Ali', enabled: '1' },
		{ '.name': 'ds2', label: 'off', enabled: '0' }
	],
	routing_mode: [
		{ '.name': 'm_rule', label: 'Rule', enabled: '1' },
		{ '.name': 'm_off', enabled: '0' }
	],
	homeproxy: [
		{ '.name': 'routing', default_mode: 'm_off' }
	],
	routing_rule: [
		{ '.name': 'rr1', label: 'ads', routing_mode: 'm_rule' },
		{ '.name': 'rr2', label: 'ads', routing_mode: 'm_off' },
		{ '.name': 'rr3', label: 'cn', routing_mode: 'm_gone' },
		{ '.name': 'rr4', label: 'cn' }
	]
};

const uci = {
	sections: (_conf, type, cb) => {
		const list = sections[type] || [];
		if (cb)
			list.forEach(cb);
		return list;
	},
	get: (_conf, name, opt) => {
		const res = Object.values(sections).flat().find((s) => s['.name'] === name);
		return (opt && res) ? res[opt] : res;
	}
};

let rendered;
const ui = {
	Select: class {
		constructor(value, choices, opts) { rendered = { value, choices, sort: opts.sort }; }
		render() { return rendered; }
	}
};

const common = loadLuciModule(file, { uci, ui });

/* the subset of a LuCI form option the helpers touch */
function option(props) {
	return Object.assign({
		values: {},
		keylist: [ 'stale' ],
		vallist: [ 'stale' ],
		cfgvalue(sid) { return this.values[sid]; },
		cbid: (sid) => `cbid.homeproxy.${sid}.x`,
		validate: () => true,
		map: { readonly: false },
		value(k, v) { (this.listed = this.listed || []).push([ k, v ]); },
		super(method, ...args) { this.called = [ method, ...args ]; return method; }
	}, props);
}

let failed = 0, checks = 0;
function check(ok, label, got) {
	checks++;
	if (!ok)
		failed++;
	console.log(`${ok ? 'PASS' : 'FAIL'}: ${label}${ok ? '' : ` (got ${JSON.stringify(got)})`}`);
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/* renderWidget */
let o = option({ default: undefined });
common.bindSectionSelect(o, 'homeproxy', 'routing_node', { '': 'Direct' }, true);
o.renderWidget('rn1', 0, null);
check(same(rendered.sort, [ '', 'rn2', 'toString' ]), 'choices skip the own and disabled sections', rendered.sort);
check(same(rendered.choices, { '': 'Direct', rn2: 'rn2', toString: 'odd name' }),
	'a section without label is listed by name', rendered.choices);

o = option({ default: 'direct-out' });
common.bindSectionSelect(o, 'homeproxy', 'routing_node', { 'direct-out': 'Direct' });
o.renderWidget('rn1', 0, null);
check(same(rendered.sort, [ 'direct-out', 'rn1', 'rn2', 'toString' ]), 'the own section is listed unless excluded', rendered.sort);
check(rendered.value === 'direct-out', 'an unset value renders as the default', rendered.value);
o.renderWidget('rn1', 0, 'rn2');
check(rendered.value === 'rn2', 'a stored value renders as is', rendered.value);

/* textvalue */
const textCases = [
	[ 'outbound defaulting to direct-out', { 'direct-out': 'Direct' }, 'direct-out',
		{ a: '', b: 'direct-out', c: 'rn1', d: 'rn2', e: 'gone', f: 'toString' },
		{ a: 'Direct', b: 'Direct', c: 'HK', d: 'rn2', e: 'gone', f: 'odd name' } ],
	[ 'dns server defaulting to default-dns', common.builtinDnsServers(), 'default-dns',
		{ a: '', b: 'system-dns', c: 'ds1' },
		{ a: 'Default DNS (issued by WAN)', b: 'System DNS', c: 'Ali' } ],
	[ 'outbound with an empty Default choice', { '': 'Default', 'direct-out': 'Direct' }, undefined,
		{ a: '', b: 'direct-out', c: 'rn1' },
		{ a: 'Default', b: 'Direct', c: 'HK' } ]
];
for (const [ label, fixed, def, values, want ] of textCases) {
	o = option({ default: def, values });
	common.bindSectionSelect(o, 'homeproxy', 'routing_node', fixed);
	const got = {};
	for (const sid in values)
		got[sid] = o.textvalue(sid);
	check(same(got, want), `textvalue: ${label}`, got);
}

/* load */
o = option();
const ret = common.loadSectionChoices('homeproxy', 'dns_server',
	Object.assign({ '': 'Default' }, common.builtinDnsServers())).call(o, 'cfg');
check(same(o.listed, [ [ '', 'Default' ], [ 'default-dns', 'Default DNS (issued by WAN)' ], [ 'system-dns', 'System DNS' ], [ 'ds1', 'Ali' ] ]),
	'load lists the fixed choices, then the enabled sections', o.listed);
check(o.keylist === undefined && o.vallist === undefined && ret === 'load' && same(o.called, [ 'load', 'cfg' ]),
	'load starts from an empty list and chains to the parent load', o.called);

/* rule grids by mode */
o = { subsection: { sectiontype: 'routing_rule' } };
const mode_option = option();
common.bindModeGrid(o, 'homeproxy', mode_option);
const shown = () => sections.routing_rule.map((r) => r['.name']).filter((sid) => o.subsection.filter(sid));
check(same(shown(), [ 'rr2' ]) && mode_option.default === 'm_off',
	'modes: the rows loaded first are those of the default mode, which new rules join', shown());
mode_option.load('cfg');
check(same(mode_option.listed, [ [ 'm_rule', 'Rule' ], [ 'm_off', 'm_off' ] ]) && mode_option.rmempty === false,
	'modes: a rule can be moved to any mode, a disabled one too', mode_option.listed);

const unique = common.validateUniqueLabelInMode('homeproxy', 'routing_rule');
const in_mode = (mode) => ({ section: { formvalue: (sid, opt) => (opt === 'routing_mode') ? mode : null } });
check(unique.call(in_mode('m_rule'), 'new', 'ads') !== true, 'labels: a label taken in the same mode is refused');
check(unique.call(in_mode('m_rule'), 'new', 'cn') === true, 'labels: a label used in other modes only is fine');
check(unique.call(in_mode('m_rule'), 'rr1', 'ads') === true, 'labels: a rule keeps its own label');
check(unique.call(in_mode('m_rule'), 'new', '') !== true, 'labels: an empty label is refused');

/* write */
const select = { value: 'old', events: [], dispatchEvent(ev) { this.events.push(ev.type); } };
o = option({ map: { parent: { findElement: (k, v) => (k === 'id' && v === 'cbid.homeproxy.r1.x') ? { querySelector: () => select } : null } } });
const wret = common.writeAndSyncSelect.call(o, 'r1', 'rn2');
check(wret === 'write' && same(o.called, [ 'write', 'r1', 'rn2' ]), 'write chains to the parent write', o.called);
check(select.value === 'rn2' && same(select.events, [ 'change' ]), 'write updates the grid select', select);

console.log(`${checks} checks, ${failed} failures`);
process.exit(failed ? 1 : 0);
