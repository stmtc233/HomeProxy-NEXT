/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { isEmpty, strToBool, strToInt, strToTime } from '../homeproxy.uc';

import {
	parse_dnsquery, parse_headers, parse_hosts_predefined, restrict_to_mode, rule_match_fields
} from './common.uc';
import { uciconfig, ucidnsserver, ucidnsrule } from './context.uc';

function build_custom_servers(ctx, servers) {
	const uci = ctx.uci;

	uci.foreach(uciconfig, ucidnsserver, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		let outbound = ctx.get_outbound(cfg.outbound);
		if (outbound === 'direct-out' && isEmpty(ctx.self_mark))
			outbound = null;

		const server_tag = ctx.dns_tag(cfg['.name']);

		if (cfg.type === 'hosts') {
			push(servers, {
				tag: server_tag,
				type: 'hosts',
				path: isEmpty(cfg.hosts_path) ? null : cfg.hosts_path,
				predefined: parse_hosts_predefined(cfg.hosts_predefined)
			});
			return;
		}

		if (cfg.type === 'dhcp') {
			push(servers, {
				tag: server_tag,
				type: 'dhcp',
				interface: cfg.dhcp_interface,
				detour: outbound
			});
			return;
		}

		push(servers, {
			tag: server_tag,
			type: cfg.type,
			server: cfg.server,
			server_port: strToInt(cfg.server_port),
			path: cfg.path,
			headers: parse_headers(cfg.headers),
			tls: cfg.tls_sni ? {
				enabled: true,
				server_name: cfg.tls_sni
			} : null,
			domain_resolver: (cfg.address_resolver || cfg.address_strategy) ? {
				server: ctx.get_resolver(cfg.address_resolver || ctx.dns_default_server),
				strategy: cfg.address_strategy
			} : null,
			detour: outbound
		});
	});
}

function build_custom_rules(ctx) {
	const uci = ctx.uci;
	const mode_rules = {};
	for (let mode in ctx.modes)
		mode_rules[mode.section] = [];

	uci.foreach(uciconfig, ucidnsrule, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		const mode = ctx.rule_mode(cfg, 'DNS rule');
		if (!mode)
			return;
		const rules = mode_rules[mode.section];

		const match_fields = {
			...rule_match_fields(ctx, cfg),
			query_type: parse_dnsquery(cfg.query_type),
			query_client_subnet: cfg.query_client_subnet,
			query_dnssec: strToBool(cfg.query_dnssec)
		};
		const match_keys = [...keys(match_fields), 'match_response', 'ip_cidr', 'ip_is_private',
		                    'response_rcode', 'response_answer', 'response_ns', 'response_extra'];

		const rule = {
			...match_fields,
			race: strToBool(cfg.race),
			speculative: strToBool(cfg.speculative),
			action: cfg.action,
			server: ctx.get_resolver(cfg.server),
			disable_cache: strToBool(cfg.dns_disable_cache),
			disable_optimistic_cache: strToBool(cfg.disable_optimistic_cache),
			rewrite_ttl: strToInt(cfg.rewrite_ttl),
			timeout: strToTime(cfg.dns_timeout),
			client_subnet: cfg.client_subnet,
			remove_client_subnet: strToBool(cfg.remove_client_subnet),
			method: cfg.reject_method,
			no_drop: strToBool(cfg.reject_no_drop),
			rcode: cfg.predefined_rcode,
			answer: cfg.predefined_answer,
			ns: cfg.predefined_ns,
			extra: cfg.predefined_extra
		};

		if (cfg.action === 'evaluate')
			rule.tag = cfg.evaluate_tag || null;

		if (cfg.match_response && cfg.match_response !== '0')
			rule.match_response = (cfg.match_response === '1') ? true : cfg.match_response;

		rule.response_rcode = cfg.response_rcode;
		rule.response_answer = cfg.response_answer;
		rule.response_ns = cfg.response_ns;
		rule.response_extra = cfg.response_extra;

		const legacy_filter = !isEmpty(cfg.ip_cidr) || strToBool(cfg.ip_is_private) === true;
		if (legacy_filter && !rule.match_response && cfg.action === 'route') {
			const eval_tag = '_hp_eval_' + cfg['.name'];
			push(rules, restrict_to_mode({
				action: 'evaluate',
				server: ctx.get_resolver(cfg.server),
				tag: eval_tag,
				...match_fields
			}, mode.name, match_keys));
			rule.match_response = eval_tag;
		}

		if (rule.match_response) {
			rule.ip_cidr = cfg.ip_cidr;
			rule.ip_is_private = strToBool(cfg.ip_is_private);
		}

		if ((rule.action === 'route' || rule.action === 'evaluate') && isEmpty(rule.server)) {
			warn(sprintf("homeproxy: DNS rule '%s' has no server configured, skipping it.\n", cfg['.name']));
			return;
		}

		if (rule.action === 'respond' && !length(filter(rules, (r) => r.action === 'evaluate'))) {
			warn(sprintf("homeproxy: DNS rule '%s' responds without a preceding evaluate rule, skipping it.\n", cfg['.name']));
			return;
		}

		push(rules, restrict_to_mode(rule, mode.name, match_keys));
	});

	/* each mode ends in its own fallback, dns.final is only reached without the clash API */
	const rules = [];
	for (let mode in ctx.modes) {
		for (let rule in mode_rules[mode.section])
			push(rules, rule);
		push(rules, {
			clash_mode: mode.name,
			action: 'route',
			server: ctx.get_resolver(mode.dns_server)
		});
	}

	return rules;
}

export function build(ctx) {
	const dns = {
		servers: [
			{
				tag: 'default-dns',
				type: 'udp',
				server: ctx.wan_dns,
				detour: ctx.self_mark ? 'direct-out' : null
			},
			{
				tag: 'system-dns',
				type: 'local',
				detour: ctx.self_mark ? 'direct-out' : null
			}
		],
		rules: [],
		strategy: ctx.dns_default_strategy,
		disable_cache: strToBool(ctx.dns_disable_cache),
		disable_expire: strToBool(ctx.dns_disable_cache_expire),
		client_subnet: ctx.dns_client_subnet,
		optimistic: (ctx.dns_optimistic_cache === '1') ? {
			enabled: true,
			timeout: !isEmpty(ctx.dns_optimistic_timeout) ? ctx.dns_optimistic_timeout : '3d'
		} : null,
		timeout: !isEmpty(ctx.dns_query_timeout) ? strToTime(ctx.dns_query_timeout) : null
	};

	build_custom_servers(ctx, dns.servers);
	dns.rules = build_custom_rules(ctx);
	dns.final = ctx.get_resolver(ctx.dns_default_server);

	return dns;
};
