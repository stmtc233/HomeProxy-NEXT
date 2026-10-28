/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { isEmpty, strToBool, strToInt, strToTime } from '../homeproxy.uc';

import {
	parse_dnsquery, parse_dnsserver, parse_headers, parse_hosts_predefined, restrict_to_modes, rule_match_fields
} from './common.uc';
import { uciconfig, ucimain, ucidnsserver, ucidnsrule } from './context.uc';

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
	const rules = [];

	uci.foreach(uciconfig, ucidnsrule, (cfg) => {
		if (cfg.enabled !== '1')
			return;

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
			push(rules, restrict_to_modes({
				action: 'evaluate',
				server: ctx.get_resolver(cfg.server),
				tag: eval_tag,
				...match_fields
			}, cfg.clash_mode, match_keys));
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

		push(rules, restrict_to_modes(rule, cfg.clash_mode, match_keys));
	});

	return rules;
}

export function build(ctx) {
	const uci = ctx.uci;
	const routing_mode = ctx.routing_mode;

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

	if (!isEmpty(ctx.main_node)) {
		push(dns.servers, {
			tag: 'main-dns',
			domain_resolver: {
				server: 'default-dns',
				strategy: (ctx.ipv6_support !== '1') ? 'ipv4_only' : null
			},
			detour: 'main-out',
			...parse_dnsserver(ctx.dns_server, 'tcp')
		});
		dns.final = 'main-dns';

		if (length(ctx.direct_domain_list))
			push(dns.rules, {
				rule_set: 'direct-domain',
				action: 'route',
				server: (routing_mode === 'bypass_mainland_china') ? 'china-dns' : 'default-dns'
			});

		if (uci.get(uciconfig, ucimain, 'block_https_rr') !== '0')
			push(dns.rules, {
				query_type: [64, 65],
				action: 'reject'
			});

		if (routing_mode === 'bypass_mainland_china') {
			push(dns.servers, {
				tag: 'china-dns',
				domain_resolver: {
					server: 'default-dns',
					strategy: (ctx.ipv6_support !== '1') ? 'ipv4_only' : null
				},
				detour: ctx.self_mark ? 'direct-out' : null,
				...parse_dnsserver(ctx.china_dns_server)
			});

			push(dns.rules, {
				query_type: [35],
				domain_suffix: ['r.10086.cn', '10086.cn', 'pub.3gppnetwork.org'],
				action: 'route',
				server: 'default-dns'
			});

			if (length(ctx.proxy_domain_list))
				push(dns.rules, {
					rule_set: 'proxy-domain',
					action: 'route',
					server: 'main-dns'
				});

			push(dns.rules, {
				rule_set: 'geosite-cn',
				action: 'route',
				server: 'china-dns'
			});

			if (uci.get(uciconfig, ucimain, 'cn_ip_fallback') === '1') {
				push(dns.rules, {
					action: 'evaluate',
					server: 'main-dns',
					tag: 'cn-fallback'
				});
				push(dns.rules, {
					match_response: 'cn-fallback',
					rule_set: 'geoip-cn',
					action: 'route',
					server: 'china-dns'
				});
			}
		}
	} else if (ctx.is_custom_mode) {
		build_custom_servers(ctx, dns.servers);
		dns.rules = build_custom_rules(ctx);
		dns.final = ctx.get_resolver(ctx.dns_default_server);
	}

	return dns;
};
