#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 ImmortalWrt.org
 */

'use strict';

import { cursor } from 'uci';

import { HP_DIR } from 'homeproxy';

/*
 * The default routing template. The modes, switched in the dashboard, each
 * come with their own rules and fallbacks:
 *   Rule          mainland China direct, ads blocked, the rest through Proxy
 *   RuleAllowAds  the same without blocking ads
 *   Global        everything through Proxy
 *   Direct        everything direct
 * Proxy is a selector of Auto (an urltest of all nodes), every node and
 * direct. The rule-sets start from the copies the package ships, so the first
 * start downloads nothing; sing-box keeps them up to date afterwards.
 *
 *   apply_template.uc        replace the routing sections with the template
 *   apply_template.uc add    add the template modes that are missing (by
 *                            section name or mode name), with what they use
 *   apply_template.uc seed   on install or upgrade: the template for a config
 *                            without routing sections; one from before the
 *                            modes keeps its rules in a mode named Custom and
 *                            gets the template next to them
 */

const uciconfig = 'homeproxy';
const TEMPLATE_TYPES = ['routing_mode', 'routing_node', 'routing_rule', 'dns_server', 'dns_rule', 'ruleset'];
const RULE_TYPES = ['routing_rule', 'dns_rule'];

function ruleset(label, url, file) {
	return {
		label: label,
		type: 'remote',
		format: 'binary',
		url: url,
		initial_path: `${HP_DIR}/resources/${file}`,
		update_interval: '1d'
	};
}

/* HTTPS / SVCB records would steer clients to ECH, which some proxies cannot carry */
function no_https_records(mode) {
	return ['dns_rule', `dr_${mode}_https_rr`, { label: 'No HTTPS records', routing_mode: `m_${mode}`, query_type: ['64', '65'], action: 'reject' }];
}

/* Rule and RuleAllowAds differ only in blocking ads */
function rule_mode_rules(mode, block_ads) {
	const m = `m_${mode}`;
	const sections = [no_https_records(mode)];
	if (block_ads)
		push(sections,
			['dns_rule', `dr_${mode}_ads`, { label: 'Block ads', routing_mode: m, rule_set: ['rs_ads'], action: 'reject' }],
			['routing_rule', `rr_${mode}_ads`, { label: 'Block ads', routing_mode: m, rule_set: ['rs_ads'], action: 'reject' }]);
	push(sections,
		['dns_rule', `dr_${mode}_china`, { label: 'China domains', routing_mode: m, rule_set: ['rs_geosite_cn'], action: 'route', server: 'ds_china' }],
		['routing_rule', `rr_${mode}_china_site`, { label: 'China domains', routing_mode: m, rule_set: ['rs_geosite_cn'], action: 'route', outbound: 'direct-out' }],
		['routing_rule', `rr_${mode}_resolve`, { label: 'Resolve', routing_mode: m, action: 'resolve' }],
		['routing_rule', `rr_${mode}_china_ip`, { label: 'China IPs', routing_mode: m, rule_set: ['rs_geoip_cn'], action: 'route', outbound: 'direct-out' }]);
	return sections;
}

const PROXY = { default_outbound: 'rn_proxy', default_server: 'ds_remote' };

const SECTIONS = [
	['routing_mode', 'm_rule', { label: 'Rule', ...PROXY }],
	['routing_mode', 'm_rule_allow_ads', { label: 'RuleAllowAds', ...PROXY }],
	['routing_mode', 'm_global', { label: 'Global', ...PROXY }],
	['routing_mode', 'm_direct', { label: 'Direct', default_outbound: 'direct-out', default_server: 'ds_china' }],

	['routing_node', 'rn_auto', { label: 'Auto', node: 'urltest', urltest_nodes: ['all-nodes'] }],
	['routing_node', 'rn_proxy', {
		label: 'Proxy',
		node: 'selector',
		selector_nodes: ['rn_auto', 'all-nodes', 'direct-out'],
		selector_default: 'rn_auto'
	}],

	['dns_server', 'ds_remote', { label: 'Remote DNS', type: 'tcp', server: '8.8.8.8', outbound: 'rn_proxy' }],
	['dns_server', 'ds_china', { label: 'China DNS', type: 'udp', server: '223.5.5.5', outbound: 'direct-out' }],

	['ruleset', 'rs_geoip_cn', ruleset('geoip-cn',
		'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs', 'geoip_cn.srs')],
	['ruleset', 'rs_geosite_cn', ruleset('geosite-cn',
		'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs', 'geosite_cn.srs')],
	['ruleset', 'rs_ads', ruleset('geosite-ads',
		'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs', 'geosite_ads.srs')],

	...rule_mode_rules('rule', true),
	...rule_mode_rules('rule_allow_ads', false),
	no_https_records('global')
];

const uci = cursor();
uci.load(uciconfig);

function sections_of(types) {
	const names = [];
	for (let section_type in types)
		uci.foreach(uciconfig, section_type, (cfg) => {
			push(names, cfg['.name']);
		});
	return names;
}

function add_template(sections) {
	for (let s in sections) {
		const section_type = s[0], name = s[1];
		uci.set(uciconfig, name, section_type);
		uci.set(uciconfig, name, 'enabled', '1');
		if (section_type in RULE_TYPES)
			uci.set(uciconfig, name, 'mode', 'default');
		for (let k, v in s[2])
			uci.set(uciconfig, name, k, v);
	}
}

if (ARGV[0] === 'seed' && length(sections_of(['routing_mode'])))
	exit(0);

/* a mode is left out when its section or its name is taken, its rules go with it */
if (ARGV[0] === 'add') {
	const names = {}, skipped = {};
	uci.foreach(uciconfig, 'routing_mode', (cfg) => {
		names[lc(trim(cfg.label || '') || cfg['.name'])] = true;
	});
	for (let s in SECTIONS)
		if (s[0] === 'routing_mode' && (uci.get(uciconfig, s[1]) || names[lc(s[2].label)]))
			skipped[s[1]] = true;

	add_template(filter(SECTIONS, (s) => !uci.get(uciconfig, s[1]) && !skipped[s[1]] && !skipped[s[2].routing_mode]));
	uci.commit(uciconfig);
	exit(0);
}

/* before the modes, one default outbound and DNS server stood for every rule */
const old_outbound = uci.get(uciconfig, 'routing', 'default_outbound'),
      old_server = uci.get(uciconfig, 'dns', 'default_server'),
      client_on = (old_outbound && old_outbound !== 'nil');
uci.delete(uciconfig, 'routing', 'default_outbound');
uci.delete(uciconfig, 'dns', 'default_server');

let default_mode = 'm_rule';
const existing = sections_of(TEMPLATE_TYPES);

if (ARGV[0] === 'seed' && (length(existing) || client_on)) {
	uci.set(uciconfig, 'm_custom', 'routing_mode');
	uci.set(uciconfig, 'm_custom', 'label', 'Custom');
	uci.set(uciconfig, 'm_custom', 'enabled', '1');
	uci.set(uciconfig, 'm_custom', 'default_outbound', client_on ? old_outbound : 'direct-out');
	uci.set(uciconfig, 'm_custom', 'default_server', old_server || 'default-dns');
	for (let name in sections_of(RULE_TYPES)) {
		uci.set(uciconfig, name, 'routing_mode', 'm_custom');
		uci.delete(uciconfig, name, 'clash_mode');
	}

	/* the client stays off if it was */
	default_mode = client_on ? 'm_custom' : 'nil';
	if (length(filter(SECTIONS, (s) => s[1] in existing)))
		warn('homeproxy: some sections are named like those of the routing template, leaving it out.\n');
	else
		add_template(SECTIONS);
} else {
	for (let name in existing)
		uci.delete(uciconfig, name);
	add_template(SECTIONS);
}

if (!uci.get(uciconfig, 'routing'))
	uci.set(uciconfig, 'routing', uciconfig);
uci.set(uciconfig, 'routing', 'default_mode', default_mode);

uci.commit(uciconfig);
