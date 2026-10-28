/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { isnan } from 'math';

import { isEmpty, parseURL, strToBool, strToInt, validation } from '../homeproxy.uc';

export function parse_port(strport) {
	if (type(strport) !== 'array' || isEmpty(strport))
		return null;

	let ports = [];
	for (let i in strport)
		push(ports, int(i));

	return ports;

};

export function parse_dnsserver(server_addr, default_protocol) {
	if (isEmpty(server_addr))
		return null;

	if (!match(server_addr, /:\/\//))
		server_addr = (default_protocol || 'udp') + '://' + (validation('ip6addr', server_addr) ? `[${server_addr}]` : server_addr);
	server_addr = parseURL(server_addr);

	return {
		type: server_addr.protocol,
		server: server_addr.hostname,
		server_port: strToInt(server_addr.port),
		path: (server_addr.pathname !== '/') ? server_addr.pathname : null,
	}
};

export function parse_dnsquery(strquery) {
	if (type(strquery) !== 'array' || isEmpty(strquery))
		return null;

	let querys = [];
	for (let i in strquery)
		isnan(int(i)) ? push(querys, i) : push(querys, int(i));

	return querys;

};

/* "domain ip [ip ...]" entries -> { domain: ip | [ip, ...] } */
export function parse_hosts_predefined(entries) {
	if (type(entries) !== 'array' || isEmpty(entries))
		return null;

	const predefined = {};
	for (let entry in entries) {
		const fields = filter(split(trim(entry), /[ \t,]+/), (v) => !isEmpty(v));
		if (length(fields) < 2)
			continue;

		const domain = shift(fields);
		predefined[domain] = [...(predefined[domain] || []), ...fields];
	}

	if (isEmpty(predefined))
		return null;

	for (let domain in predefined)
		if (length(predefined[domain]) === 1)
			predefined[domain] = predefined[domain][0];

	return predefined;
};

export function parse_headers(headers) {
	if (isEmpty(headers))
		return null;

	if (type(headers) === 'object')
		return headers;

	const lines = (type(headers) === 'array') ? headers : [headers];
	const out = {};
	for (let line in lines) {
		const pos = index(line, ':');
		if (pos > 0)
			out[trim(substr(line, 0, pos))] = trim(substr(line, pos + 1));
	}

	return isEmpty(out) ? null : out;
};

/* match fields shared by routing_rule and dns_rule */
export function rule_match_fields(ctx, cfg) {
	return {
		ip_version: strToInt(cfg.ip_version),
		network: cfg.network,
		protocol: cfg.protocol,
		domain: cfg.domain,
		domain_suffix: cfg.domain_suffix,
		domain_keyword: cfg.domain_keyword,
		domain_regex: cfg.domain_regex,
		source_ip_cidr: cfg.source_ip_cidr,
		source_ip_is_private: strToBool(cfg.source_ip_is_private),
		source_mac_address: cfg.source_mac_address,
		source_hostname: cfg.source_hostname,
		source_port: parse_port(cfg.source_port),
		source_port_range: cfg.source_port_range,
		port: parse_port(cfg.port),
		port_range: cfg.port_range,
		process_name: cfg.process_name,
		process_path: cfg.process_path,
		process_path_regex: cfg.process_path_regex,
		user: cfg.user,
		rule_set: ctx.get_ruleset(cfg.rule_set),
		rule_set_ip_cidr_match_source: strToBool(cfg.rule_set_ip_cidr_match_source),
		invert: strToBool(cfg.invert)
	};
};

function is_match_value(v) {
	return !(v === null || v === '' || v === false || (type(v) === 'array' && !length(v)));
}

/*
 * Limit a rule to some clash modes. One mode is just another match field,
 * unless an invert would flip it as well; otherwise the match fields move
 * into a logical rule next to the modes. sing-box refuses an empty sub-rule,
 * so a rule without match fields only gets the modes.
 */
export function restrict_to_modes(rule, modes, match_keys) {
	if (type(modes) === 'string')
		modes = [modes];
	if (isEmpty(modes))
		return rule;

	const match = {},
	      outer = {};
	for (let k in keys(rule)) {
		if (!(k in match_keys))
			outer[k] = rule[k];
		else if (is_match_value(rule[k]))
			match[k] = rule[k];
	}

	const mode_rules = map(modes, (m) => {
		return { clash_mode: m };
	});
	const mode_rule = (length(modes) === 1) ? mode_rules[0] : {
		type: 'logical',
		mode: 'or',
		rules: mode_rules
	};

	if (!length(keys(match)))
		return { ...mode_rule, ...outer };
	if (length(modes) === 1 && match.invert !== true)
		return { ...match, clash_mode: modes[0], ...outer };

	return {
		type: 'logical',
		mode: 'and',
		rules: [mode_rule, match],
		...outer
	};
};
