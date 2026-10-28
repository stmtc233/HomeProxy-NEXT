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
 * The default routing template. The default outbound is the selector Proxy
 * (an urltest of all nodes, every node and direct), and the rules make the
 * clash modes, switched in the dashboard:
 *   Rule          mainland China direct, ads blocked, the rest through Proxy
 *   RuleAllowAds  the same without blocking ads
 *   Global        everything through Proxy
 *   Direct        everything direct
 * The rule-sets start from the copies the package ships, so the first start
 * downloads nothing; sing-box keeps them up to date afterwards.
 *
 *   apply_template.uc        replace the routing sections with the template
 *   apply_template.uc seed   the same, but only if there are none yet
 */

const uciconfig = 'homeproxy';
const TEMPLATE_TYPES = ['routing_node', 'routing_rule', 'dns_server', 'dns_rule', 'ruleset'];

/* sing-box lists only the modes some rule names, so the rule modes name both */
const RULE_MODES = ['Rule', 'RuleAllowAds'];

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

const SECTIONS = [
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

	/* HTTPS / SVCB records would steer clients to ECH, which some proxies cannot carry */
	['dns_rule', 'dr_https_rr', { label: 'No HTTPS records', query_type: ['64', '65'], action: 'reject' }],
	['dns_rule', 'dr_direct', { label: 'Direct mode', clash_mode: ['Direct'], action: 'route', server: 'ds_china' }],
	['dns_rule', 'dr_global', { label: 'Global mode', clash_mode: ['Global'], action: 'route', server: 'ds_remote' }],
	['dns_rule', 'dr_ads', { label: 'Block ads', clash_mode: ['Rule'], rule_set: ['rs_ads'], action: 'reject' }],
	['dns_rule', 'dr_china', { label: 'China domains', clash_mode: RULE_MODES, rule_set: ['rs_geosite_cn'], action: 'route', server: 'ds_china' }],

	['routing_rule', 'rr_direct', { label: 'Direct mode', clash_mode: ['Direct'], action: 'route', outbound: 'direct-out' }],
	['routing_rule', 'rr_global', { label: 'Global mode', clash_mode: ['Global'], action: 'route', outbound: 'rn_proxy' }],
	['routing_rule', 'rr_ads', { label: 'Block ads', clash_mode: ['Rule'], rule_set: ['rs_ads'], action: 'reject' }],
	['routing_rule', 'rr_china_site', { label: 'China domains', clash_mode: RULE_MODES, rule_set: ['rs_geosite_cn'], action: 'route', outbound: 'direct-out' }],
	['routing_rule', 'rr_resolve', { label: 'Resolve', clash_mode: RULE_MODES, action: 'resolve' }],
	['routing_rule', 'rr_china_ip', { label: 'China IPs', clash_mode: RULE_MODES, rule_set: ['rs_geoip_cn'], action: 'route', outbound: 'direct-out' }]
];

const SETTINGS = {
	routing: { default_outbound: 'rn_proxy' },
	dns: { default_server: 'ds_remote' }
};

const uci = cursor();
uci.load(uciconfig);

const existing = [];
for (let section_type in TEMPLATE_TYPES)
	uci.foreach(uciconfig, section_type, (cfg) => {
		push(existing, cfg['.name']);
	});

if (ARGV[0] === 'seed' && length(existing))
	exit(0);

for (let name in existing)
	uci.delete(uciconfig, name);

for (let s in SECTIONS) {
	const section_type = s[0], name = s[1];
	uci.set(uciconfig, name, section_type);
	uci.set(uciconfig, name, 'enabled', '1');
	if (section_type in ['routing_rule', 'dns_rule'])
		uci.set(uciconfig, name, 'mode', 'default');
	for (let k, v in s[2])
		uci.set(uciconfig, name, k, v);
}

for (let section, options in SETTINGS) {
	if (!uci.get(uciconfig, section))
		uci.set(uciconfig, section, uciconfig);
	for (let k, v in options)
		uci.set(uciconfig, section, k, v);
}

uci.commit(uciconfig);
