/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { access } from 'fs';

import { isEmpty, strToBool, strToInt, strToTime, strToMs, HP_DIR } from '../homeproxy.uc';

import { restrict_to_modes, rule_match_fields } from './common.uc';
import { uciconfig, uciroutingsetting, uciroutingrule, uciruleset } from './context.uc';

function build_main(ctx, route) {
	const routing_mode = ctx.routing_mode;

	route.default_domain_resolver = {
		server: 'default-dns',
		strategy: (ctx.ipv6_support !== '1') ? 'prefer_ipv4' : null
	};

	if (length(ctx.direct_domain_list))
		push(route.rules, {
			rule_set: 'direct-domain',
			action: 'route',
			outbound: 'direct-out'
		});

	if (ctx.dedicated_udp_node) {
		const udp_override = ctx.direct_overrides[ctx.main_udp_node] || null;
		push(route.rules, {
			network: 'udp',
			action: 'route',
			outbound: 'main-udp-out',
			override_address: udp_override ? udp_override.override_address : null,
			override_port: udp_override ? udp_override.override_port : null
		});
	}

	if (routing_mode === 'bypass_mainland_china') {
		push(route.rules, {
			action: 'resolve',
			strategy: (ctx.ipv6_support !== '1') ? 'prefer_ipv4' : null
		});
		push(route.rules, {
			rule_set: 'geoip-cn',
			action: 'route',
			outbound: 'direct-out'
		});
	}

	const main_override = ctx.direct_overrides[ctx.main_node] || null;
	if (main_override)
		push(route.rules, {
			action: 'route-options',
			override_address: main_override.override_address,
			override_port: main_override.override_port
		});

	route.final = 'main-out';

	if (length(ctx.direct_domain_list))
		push(route.rule_set, {
			type: 'inline',
			tag: 'direct-domain',
			rules: [
				{
					domain_keyword: ctx.direct_domain_list,
				}
			]
		});

	if (length(ctx.proxy_domain_list))
		push(route.rule_set, {
			type: 'inline',
			tag: 'proxy-domain',
			rules: [
				{
					domain_keyword: ctx.proxy_domain_list,
				}
			]
		});

	if (routing_mode === 'bypass_mainland_china') {
		const preset_rulesets = [
			{
				tag: 'geoip-cn',
				path: HP_DIR + '/resources/geoip_cn.srs',
				url: 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs'
			},
			{
				tag: 'geosite-cn',
				path: HP_DIR + '/resources/geosite_cn.srs',
				url: 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs'
			}
		];

		for (let rs in preset_rulesets) {
			if (access(rs.path)) {
				push(route.rule_set, {
					type: 'local',
					tag: rs.tag,
					format: 'binary',
					path: rs.path
				});
			} else {
				push(route.rule_set, {
					type: 'remote',
					tag: rs.tag,
					format: 'binary',
					url: rs.url,
					update_interval: '24h',
					http_client: ctx.http_client_for('main-out')
				});
			}
		}
	}

	if (isEmpty(route.rule_set))
		route.rule_set = null;
}

function build_custom_rule(ctx, cfg) {
	const rule_outbound = ctx.get_outbound(cfg.outbound);
	const rule_direct_override = ctx.get_direct_override(cfg.outbound);
	let rule_override_address = cfg.override_address,
	    rule_override_port = strToInt(cfg.override_port);
	if (isEmpty(rule_override_address) && isEmpty(rule_override_port) && rule_direct_override) {
		rule_override_address = rule_direct_override.override_address;
		rule_override_port = rule_direct_override.override_port;
	}

	const match_fields = rule_match_fields(ctx, cfg);
	const rule = {
		...match_fields,
		client: cfg.client,
		ip_cidr: cfg.ip_cidr,
		ip_is_private: strToBool(cfg.ip_is_private),
		action: cfg.action,
		outbound: rule_outbound,
		override_address: rule_override_address,
		override_port: rule_override_port,
		udp_disable_domain_unmapping: strToBool(cfg.udp_disable_domain_unmapping),
		udp_connect: strToBool(cfg.udp_connect),
		udp_timeout: strToTime(cfg.udp_timeout),
		tls_fragment: strToBool(cfg.tls_fragment),
		tls_fragment_fallback_delay: strToMs(cfg.tls_fragment_fallback_delay),
		tls_record_fragment: strToBool(cfg.tls_record_fragment),
		tls_spoof: cfg.tls_spoof || null,
		tls_spoof_method: cfg.tls_spoof_method || null
	};
	if (cfg.action === 'resolve') {
		rule.server = ctx.get_resolver(cfg.resolve_server);
		rule.strategy = cfg.resolve_strategy;
		rule.disable_cache = strToBool(cfg.resolve_disable_cache);
		rule.disable_optimistic_cache = strToBool(cfg.resolve_disable_optimistic_cache);
		rule.rewrite_ttl = strToInt(cfg.resolve_rewrite_ttl);
		rule.timeout = strToTime(cfg.resolve_timeout);
		rule.client_subnet = cfg.resolve_client_subnet;
	}
	if (cfg.action === 'reject') {
		rule.method = cfg.reject_method;
		rule.no_drop = strToBool(cfg.reject_no_drop);
	}
	/* route applies both fragment modes, route-options refuses the pair */
	if (cfg.action === 'route-options' && rule.tls_fragment && rule.tls_record_fragment) {
		warn(sprintf("homeproxy: routing rule '%s' enables both TLS fragment and TLS record fragment on route-options, keeping TLS record fragment only.\n", cfg['.name']));
		rule.tls_fragment = null;
		rule.tls_fragment_fallback_delay = null;
	}

	return restrict_to_modes(rule, cfg.clash_mode, [...keys(match_fields), 'client', 'ip_cidr', 'ip_is_private']);
}

function build_custom_ruleset(ctx, cfg) {
	const extra_tags = cfg.extra_tags || [];
	let rs_tag = ctx.ruleset_tag(cfg['.name']);
	if (length(extra_tags) && cfg.type !== 'inline') {
		rs_tag = [rs_tag];
		for (let t in extra_tags)
			push(rs_tag, t);
		const fetch_ref = (cfg.type === 'remote') ? (cfg.url || '') : (cfg.path || '');
		if (!match(fetch_ref, /\{tag\}/))
			warn(sprintf("homeproxy: rule-set '%s' uses extra tags but its %s source lacks a {tag} placeholder.\n", cfg['.name'], cfg.type));
		if (cfg.type === 'remote' && !isEmpty(cfg.initial_path) && !match(cfg.initial_path, /\{tag\}/))
			warn(sprintf("homeproxy: rule-set '%s' uses extra tags but its initial_path lacks a {tag} placeholder.\n", cfg['.name']));
	}

	const ruleset = {
		type: cfg.type,
		tag: rs_tag,
		format: cfg.format,
		path: cfg.path,
		url: cfg.url,
		update_interval: cfg.update_interval
	};
	if (cfg.type === 'remote')
		ruleset.http_client = ctx.http_client_for(ctx.get_outbound(cfg.outbound) || ctx.get_outbound(ctx.default_outbound));
	if (cfg.type === 'remote' && !isEmpty(cfg.initial_path))
		ruleset.initial_path = cfg.initial_path;

	return ruleset;
}

function build_custom(ctx, route) {
	const uci = ctx.uci;

	route.default_domain_resolver = {
		server: ctx.get_resolver(ctx.default_outbound_dns)
	};

	if (uci.get(uciconfig, uciroutingsetting, 'find_neighbor') === '1')
		route.find_neighbor = true;

	if (ctx.domain_strategy)
		push(route.rules, {
			action: 'resolve',
			strategy: ctx.domain_strategy
		});

	uci.foreach(uciconfig, uciroutingrule, (cfg) => {
		if (cfg.enabled !== '1')
			return null;

		push(route.rules, build_custom_rule(ctx, cfg));
	});

	const final_override = ctx.get_direct_override(ctx.default_outbound);
	if (final_override)
		push(route.rules, {
			action: 'route-options',
			override_address: final_override.override_address,
			override_port: final_override.override_port
		});

	route.final = ctx.get_outbound(ctx.default_outbound);

	uci.foreach(uciconfig, uciruleset, (cfg) => {
		if (cfg.enabled !== '1')
			return null;

		push(route.rule_set, build_custom_ruleset(ctx, cfg));
	});
}

/* needs the outbounds built first: direct-node overrides come from there */
export function build(ctx) {
	const route = {
		rules: [
			{
				inbound: 'dns-in',
				action: 'hijack-dns'
			},
			{
				action: 'sniff'
			}
		],
		rule_set: [],
		auto_detect_interface: isEmpty(ctx.default_interface) ? true : null,
		default_interface: ctx.default_interface
	};

	if (!isEmpty(ctx.main_node))
		build_main(ctx, route);
	else if (ctx.is_custom_mode)
		build_custom(ctx, route);

	if (isEmpty(route.default_domain_resolver))
		route.default_domain_resolver = { server: 'default-dns' };

	return route;
};
