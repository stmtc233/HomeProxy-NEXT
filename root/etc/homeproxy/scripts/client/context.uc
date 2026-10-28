/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { DEFAULTS, isEmpty, strToInt } from '../homeproxy.uc';

export const uciconfig = 'homeproxy';

export const uciinfra = 'infra',
             ucimain = 'config',
             ucicontrol = 'control';

export const ucidnssetting = 'dns',
             ucidnsserver = 'dns_server',
             ucidnsrule = 'dns_rule';

export const uciroutingsetting = 'routing',
             uciroutingmode = 'routing_mode',
             uciroutingnode = 'routing_node',
             uciroutingrule = 'routing_rule';

export const ucinode = 'node',
             uciruleset = 'ruleset';

/* routing nodes whose `node` names a group they build instead of a node */
export const GROUP_NODES = ['urltest', 'selector'];

/*
 * Tags follow the section label (subscription nodes have md5 section names).
 * Sections without a label keep the old 'cfg-<name>-<suffix>' form.
 */
function build_tags(sections, reserved, suffix) {
	const tags = {};
	const used = {};
	for (let t in reserved)
		used[t] = true;

	for (let cfg in sections) {
		const name = cfg['.name'];
		let label = trim(cfg.label || '');
		if (isEmpty(label))
			label = 'cfg-' + name + '-' + suffix;

		/* labels from different subscriptions may clash, tags must be unique */
		let tag = label;
		for (let n = 2; used[tag]; n++)
			tag = `${label} #${n}`;

		used[tag] = true;
		tags[name] = tag;
	}

	return tags;
}

/*
 * Everything the client config is built from: the settings read once from
 * UCI, the section -> tag maps, the lookups that need the cursor, and the
 * state the builders share (direct node overrides, download clients).
 */
export function load(uci, ubus) {
	const ctx = {
		uci: uci,
		direct_overrides: {},
		http_clients: []
	};

	ctx.wan_dns = ubus.call('network.interface', 'status', {'interface': 'wan'})?.['dns-server']?.[0] || '223.5.5.5';

	ctx.dns_port = uci.get(uciconfig, uciinfra, 'dns_port') || DEFAULTS.infra.dns_port;
	ctx.ntp_server = uci.get(uciconfig, uciinfra, 'ntp_server') || DEFAULTS.infra.ntp_server;
	ctx.ipv6_support = uci.get(uciconfig, ucimain, 'ipv6_support') || '0';

	ctx.dns_default_strategy = uci.get(uciconfig, ucidnssetting, 'default_strategy');
	ctx.dns_disable_cache = uci.get(uciconfig, ucidnssetting, 'disable_cache');
	ctx.dns_disable_cache_expire = uci.get(uciconfig, ucidnssetting, 'disable_cache_expire');
	ctx.dns_client_subnet = uci.get(uciconfig, ucidnssetting, 'client_subnet');

	ctx.default_outbound_dns = uci.get(uciconfig, uciroutingsetting, 'default_outbound_dns') || DEFAULTS.routing.default_outbound_dns;
	ctx.domain_strategy = uci.get(uciconfig, uciroutingsetting, 'domain_strategy');

	/* the firewall sends mainland China past sing-box, so Global could not proxy everything */
	ctx.bypass_cn_traffic = (uci.get(uciconfig, uciroutingsetting, 'bypass_cn_traffic') === '1');

	/*
	 * The routing modes, switched in the dashboard (sing-box calls them clash
	 * modes, named by the label). Each has its own rules and its own outbound
	 * and DNS server for what none of them matches.
	 */
	ctx.modes = [];
	const modes_by_section = {};
	uci.foreach(uciconfig, uciroutingmode, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		const mode = {
			section: cfg['.name'],
			name: trim(cfg.label || '') || cfg['.name'],
			outbound: cfg.default_outbound || DEFAULTS.routing_mode.default_outbound,
			dns_server: cfg.default_server || DEFAULTS.routing_mode.default_server
		};
		if (ctx.bypass_cn_traffic && lc(mode.name) === 'global') {
			warn("homeproxy: the Global mode is not available while bypass_cn_traffic is on, skipping it.\n");
			return;
		}

		push(ctx.modes, mode);
		modes_by_section[mode.section] = mode;
	});
	if (!length(ctx.modes))
		die('No routing mode is enabled, please check your configuration.');

	const default_mode = uci.get(uciconfig, uciroutingsetting, 'default_mode');
	ctx.default_mode = modes_by_section[default_mode];
	if (!ctx.default_mode) {
		ctx.default_mode = ctx.modes[0];
		warn(sprintf("homeproxy: the default mode '%s' is not available, starting in %s.\n", default_mode, ctx.default_mode.name));
	}
	ctx.default_outbound = ctx.default_mode.outbound;
	ctx.dns_default_server = ctx.default_mode.dns_server;

	/* the mode a rule belongs to, null when that one is disabled or missing */
	ctx.rule_mode = function(cfg, kind) {
		const mode = modes_by_section[cfg.routing_mode];
		if (!mode && (isEmpty(cfg.routing_mode) || uci.get(uciconfig, cfg.routing_mode, '.type') !== uciroutingmode))
			warn(sprintf("homeproxy: %s '%s' belongs to no routing mode, skipping it.\n", kind, cfg['.name']));
		return mode;
	};

	ctx.dns_optimistic_cache = uci.get(uciconfig, ucidnssetting, 'optimistic_cache') || '0';
	ctx.dns_optimistic_timeout = uci.get(uciconfig, ucidnssetting, 'optimistic_timeout');
	ctx.dns_query_timeout = uci.get(uciconfig, ucidnssetting, 'dns_timeout');
	ctx.dns_store_dns = uci.get(uciconfig, ucidnssetting, 'cache_file_store_dns') || '0';

	const proxy_mode = uci.get(uciconfig, ucimain, 'proxy_mode') || DEFAULTS.config.proxy_mode;
	ctx.proxy_mode = proxy_mode;
	ctx.default_interface = uci.get(uciconfig, ucicontrol, 'bind_interface');

	ctx.mixed_port = uci.get(uciconfig, uciinfra, 'mixed_port') || DEFAULTS.infra.mixed_port;

	ctx.udp_timeout = uci.get(uciconfig, uciroutingsetting, 'udp_timeout');

	if (match(proxy_mode, /redirect/)) {
		ctx.self_mark = uci.get(uciconfig, 'infra', 'self_mark') || DEFAULTS.infra.self_mark;
		ctx.redirect_port = uci.get(uciconfig, 'infra', 'redirect_port') || DEFAULTS.infra.redirect_port;
	}
	if (match(proxy_mode, /tproxy/))
		ctx.tproxy_port = uci.get(uciconfig, 'infra', 'tproxy_port') || DEFAULTS.infra.tproxy_port;
	if (match(proxy_mode, /tun/)) {
		ctx.tun_name = uci.get(uciconfig, uciinfra, 'tun_name') || DEFAULTS.infra.tun_name;
		ctx.tun_addr4 = uci.get(uciconfig, uciinfra, 'tun_addr4') || DEFAULTS.infra.tun_addr4;
		ctx.tun_addr6 = uci.get(uciconfig, uciinfra, 'tun_addr6') || DEFAULTS.infra.tun_addr6;
		ctx.tun_mtu = uci.get(uciconfig, uciinfra, 'tun_mtu') || DEFAULTS.infra.tun_mtu;
		ctx.tcpip_stack = uci.get(uciconfig, uciroutingsetting, 'tcpip_stack') || DEFAULTS.routing.tcpip_stack;
		ctx.endpoint_independent_nat = uci.get(uciconfig, uciroutingsetting, 'endpoint_independent_nat');
	}

	ctx.log_level = uci.get(uciconfig, ucimain, 'log_level') || DEFAULTS.config.log_level;

	const tun_dns_mode_raw = uci.get(uciconfig, ucimain, 'tun_dns_mode'),
	      udp_mapping_raw = uci.get(uciconfig, ucimain, 'udp_mapping'),
	      udp_filtering_raw = uci.get(uciconfig, ucimain, 'udp_filtering');

	ctx.tun_dns_mode = (tun_dns_mode_raw === 'default') ? '' : tun_dns_mode_raw;
	ctx.tun_dns_address = uci.get(uciconfig, ucimain, 'tun_dns_address');
	ctx.udp_mapping = (udp_mapping_raw === 'default') ? '' : udp_mapping_raw;
	ctx.udp_filtering = (udp_filtering_raw === 'default') ? '' : udp_filtering_raw;
	ctx.udp_nat_max = strToInt(uci.get(uciconfig, ucimain, 'udp_nat_max'));

	ctx.dashboard_enabled = uci.get(uciconfig, ucimain, 'dashboard') || '0';
	ctx.dashboard_listen = uci.get(uciconfig, ucimain, 'dashboard_listen') || DEFAULTS.config.dashboard_listen;
	ctx.dashboard_secret = uci.get(uciconfig, ucimain, 'dashboard_secret');
	ctx.dashboard_url = uci.get(uciconfig, ucimain, 'dashboard_url');

	function uci_sections(section_type, cond) {
		const sections = [];
		uci.foreach(uciconfig, section_type, (cfg) => {
			if (!cond || cond(cfg))
				push(sections, cfg);
		});
		return sections;
	}

	const outbound_tags = build_tags(
		[...uci_sections(ucinode), ...uci_sections(uciroutingnode, (cfg) => cfg.node in GROUP_NODES)],
		['direct-out', 'block-out', 'any'],
		'out'
	);

	const dns_tags = build_tags(
		uci_sections(ucidnsserver),
		['default-dns', 'system-dns'],
		'dns'
	);

	/* extra tags are used verbatim (they fill the {tag} placeholder), labels give way to them */
	let ruleset_reserved = [];
	for (let cfg in uci_sections(uciruleset))
		ruleset_reserved = [...ruleset_reserved, ...(cfg.extra_tags || [])];
	const ruleset_tags = build_tags(uci_sections(uciruleset), ruleset_reserved, 'rule');

	ctx.node_tag = (name) => outbound_tags[name] || ('cfg-' + name + '-out');
	ctx.dns_tag = (name) => dns_tags[name] || ('cfg-' + name + '-dns');
	ctx.ruleset_tag = (name) => ruleset_tags[name] || ('cfg-' + name + '-rule');

	ctx.get_outbound = function(cfg) {
		if (isEmpty(cfg))
			return null;

		if (type(cfg) === 'array') {
			if ('any-out' in cfg)
				return 'any';

			let outbounds = [];
			for (let i in cfg)
				push(outbounds, ctx.get_outbound(i));
			return outbounds;
		} else {
			switch (cfg) {
			case 'block-out':
			case 'direct-out':
				return cfg;
			default:
				const node = uci.get(uciconfig, cfg, 'node');
				if (isEmpty(node))
					die(sprintf("%s's node is missing, please check your configuration.", cfg));
				else if (node in GROUP_NODES)
					return ctx.node_tag(cfg);
				else
					return ctx.node_tag(node);
			}
		}
	};

	/* only valid once the outbounds are built: they fill direct_overrides */
	ctx.get_direct_override = function(outbound_selector) {
		if (type(outbound_selector) === 'array' || isEmpty(outbound_selector))
			return null;

		switch (outbound_selector) {
		case 'direct-out':
		case 'block-out':
			return null;
		default:
			const node = uci.get(uciconfig, outbound_selector, 'node');
			return (!isEmpty(node) && !(node in GROUP_NODES)) ? (ctx.direct_overrides[node] || null) : null;
		}
	};

	ctx.get_resolver = function(cfg) {
		if (isEmpty(cfg))
			return null;

		switch (cfg) {
		case 'default-dns':
		case 'system-dns':
			return cfg;
		default:
			return ctx.dns_tag(cfg);
		}
	};

	ctx.get_ruleset = function(cfg) {
		if (isEmpty(cfg))
			return null;

		let rules = [];
		for (let i in cfg)
			push(rules, isEmpty(i) ? null : ctx.ruleset_tag(i));
		return rules;
	};

	function is_direct_outbound_tag(tag) {
		if (isEmpty(tag) || tag === 'block-out')
			return false;
		if (tag === 'direct-out')
			return true;

		const section = filter(keys(outbound_tags), (k) => outbound_tags[k] === tag)[0];
		if (isEmpty(section))
			return false;

		const node_name = uci.get(uciconfig, section, 'node') || section;
		const node = uci.get_all(uciconfig, node_name);
		return !isEmpty(node) && node.type === 'direct';
	}

	/* one download client per detour, collected in ctx.http_clients */
	const http_seen = {};
	ctx.http_client_for = function(detour) {
		if (isEmpty(detour))
			detour = ctx.get_outbound(ctx.default_outbound) || 'direct-out';

		const tag = 'hp-' + detour;
		if (http_seen[detour])
			return tag;

		http_seen[detour] = true;
		const client = { tag: tag };
		if (!(isEmpty(ctx.self_mark) && is_direct_outbound_tag(detour)))
			client.detour = detour;

		push(ctx.http_clients, client);

		return tag;
	};

	return ctx;
};
