/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { isnan } from 'math';

import { isEmpty, strToBool, strToInt } from '../homeproxy.uc';

export function parse_port(strport) {
	if (type(strport) !== 'array' || isEmpty(strport))
		return null;

	let ports = [];
	for (let i in strport)
		push(ports, int(i));

	return ports;

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
 * Limit a rule to a clash mode. The mode is just another match field, unless
 * an invert would flip it as well; then the match fields move into a logical
 * rule next to it. sing-box refuses an empty sub-rule, so a rule without match
 * fields only gets the mode.
 */
export function restrict_to_mode(rule, mode, match_keys) {
	const match = {},
	      outer = {};
	for (let k in keys(rule)) {
		if (!(k in match_keys))
			outer[k] = rule[k];
		else if (is_match_value(rule[k]))
			match[k] = rule[k];
	}

	if (!length(keys(match)))
		return { clash_mode: mode, ...outer };
	if (match.invert !== true)
		return { ...match, clash_mode: mode, ...outer };

	return {
		type: 'logical',
		mode: 'and',
		rules: [{ clash_mode: mode }, match],
		...outer
	};
};
