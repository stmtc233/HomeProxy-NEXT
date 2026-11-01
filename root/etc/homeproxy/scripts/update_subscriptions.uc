#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

'use strict';

import { md5 } from 'digest';
import { open } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';

import { init_action } from 'luci.sys';

import {
	wGETVerbose, decodeBase64Str, getTime, isEmpty, DEFAULTS, RUN_DIR
} from 'homeproxy';

import { parse_uri } from 'parse_uri';

system(`mkdir -p ${RUN_DIR}`);
/* Keep the inode: unlinking a flock file can let two updaters run at once.
 * A separate filename also avoids the legacy directory lock. */
const update_lock = open(RUN_DIR + '/update_subscriptions.flock', 'a');

if (!update_lock || !update_lock.lock('xn')) {
	warn('Another subscription update is running.\n');
	exit(2);
}

const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

const ucinode = 'node',
      ucisubscription = 'subscription';

const allow_insecure = uci.get(uciconfig, ucisubscription, 'allow_insecure') || '0',
      filter_mode = uci.get(uciconfig, ucisubscription, 'filter_nodes') || DEFAULTS.subscription.filter_nodes,
      filter_keywords = uci.get(uciconfig, ucisubscription, 'filter_keywords') || [],
      packet_encoding = uci.get(uciconfig, ucisubscription, 'packet_encoding') || DEFAULTS.subscription.packet_encoding,
      subscription_urls = uci.get(uciconfig, ucisubscription, 'subscription_url') || [],
      user_agent = uci.get(uciconfig, ucisubscription, 'user_agent');

function filter_check(name) {
	if (isEmpty(name) || filter_mode === 'disabled' || isEmpty(filter_keywords))
		return false;

	let ret = false;
	for (let i in filter_keywords) {
		let patten;
		try {
			patten = regexp(i);
		} catch(e) {
			log(sprintf('Skipping invalid filter keyword regex: %s.', i));
			continue;
		}
		if (patten && match(name, patten))
			ret = true;
	}
	if (filter_mode === 'whitelist')
		ret = !ret;

	return ret;
}

const node_cache = {},
      node_result = [];

const ubus = connect();
const sing_features = ubus.call('luci.homeproxy', 'singbox_get_features', {}) || {};
if (isEmpty(sing_features))
	log('Warning: Failed to query sing-box features via ubus, assuming defaults.');

function log(...args) {
	const logfile = open(`${RUN_DIR}/homeproxy.log`, 'a');
	logfile.write(`${getTime()} [SUBSCRIBE] ${join(' ', args)}\n`);
	logfile.close();
}

function redact(url) {
	return replace(url, /[?#].*$/, '');
}

function validation_port(port) {
	return match(port, /^\d{1,5}$/) != null && int(port) > 0 && int(port) <= 65535;
}

function node_problem(cfg) {
	if (isEmpty(cfg.address) || isEmpty(cfg.port))
		return 'missing address or port';
	if (!validation_port(cfg.port))
		return 'invalid port';

	switch (cfg.type) {
	case 'shadowsocks':
		if (isEmpty(cfg.shadowsocks_encrypt_method) || isEmpty(cfg.password))
			return 'missing shadowsocks method or password';
		break;
	case 'vless':
	case 'vmess':
		if (isEmpty(cfg.uuid))
			return 'missing uuid';
		break;
	case 'trojan':
	case 'anytls':
	case 'snell':
		if (isEmpty(cfg.password))
			return 'missing password';
		break;
	case 'tuic':
		if (isEmpty(cfg.uuid) || isEmpty(cfg.password))
			return 'missing uuid or password';
		break;
	case 'hysteria':
	case 'hysteria2':
		if (isEmpty(cfg.password) && isEmpty(cfg.hysteria_auth_payload))
			return 'missing auth';
		break;
	case 'socks':
	case 'http':
		break;
	default:
		return 'unsupported type';
	}

	return null;
}

function main() {
	for (let url in subscription_urls) {
		url = replace(url, /#.*$/, '');
		const groupHash = md5(url);
		node_cache[groupHash] = {};
		const shown_url = redact(url);

		const fetched = wGETVerbose(url, user_agent);
		if (isEmpty(fetched.content)) {
			log(sprintf('Failed to fetch resources from %s: %s', shown_url, fetched.error || 'empty response'));
			continue;
		}
		const res = fetched.content;

		let nodes;
		try {
			nodes = json(res).servers || json(res);

			if (nodes[0].server && nodes[0].method)
				map(nodes, (_, i) => nodes[i].nodetype = 'sip008');
		} catch(e) {
			if (match(res, /(^|\n)[ \t]*(proxies|proxy-groups)[ \t]*:/)) {
				log(sprintf('Unsupported subscription format (Clash/mihomo YAML) at %s.', shown_url));
				continue;
			}

			log(sprintf('JSON parse failed for %s, trying base64: %s', shown_url, e.message));
			nodes = decodeBase64Str(res);
			nodes = nodes ? split(trim(nodes), '\n') : [];
		}

		let count = 0, skipped = 0;
		for (let node in nodes) {
			if (isEmpty(node))
				continue;

			const config = parse_uri(node, sing_features, log);
			if (isEmpty(config)) {
				if (skipped < 5)
					log(sprintf('Skipping unparsable entry (%s) from %s.',
						type(node) === 'string' ? replace(node, /:.*$/, '') : type(node), shown_url));
				skipped++;
				continue;
			}

			const problem = node_problem(config);
			if (problem) {
				if (skipped < 5)
					log(sprintf('Skipping invalid node %s: %s.', config.label || config.address, problem));
				skipped++;
				continue;
			}

			const label = config.label;
			config.label = null;
			const confHash = md5(sprintf('%J', config)),
			      nameHash = md5(groupHash + label);
			config.label = label;

			if (filter_check(config.label))
				log(sprintf('Skipping blacklist node: %s.', config.label));
			else if (node_cache[groupHash][confHash] || node_cache[groupHash][nameHash])
				log(sprintf('Skipping duplicate node: %s.', config.label));
			else {
				if (config.tls === '1' && allow_insecure === '1')
					config.tls_insecure = '1';
				if (config.type in ['vless', 'vmess'])
					config.packet_encoding = packet_encoding;

				config.grouphash = groupHash;
				push(node_result, []);
				push(node_result[length(node_result)-1], config);
				node_cache[groupHash][confHash] = config;
				node_cache[groupHash][nameHash] = config;

				count++;
			}
		}

		if (skipped > 0)
			log(sprintf('%s entries skipped from %s.', skipped, shown_url));

		if (count === 0)
			log(sprintf('No valid node found in %s.', shown_url));
		else
			log(sprintf('Successfully fetched %s nodes of total %s from %s.', count, length(nodes), shown_url));
	}

	if (isEmpty(node_result)) {
		log('Failed to update subscriptions: no valid node found.');
		return false;
	}

	let added = 0, removed = 0, changed = false;
	uci.foreach(uciconfig, ucinode, (cfg) => {
		if (!cfg.grouphash)
			return null;

		/* Preserve a configured subscription on download/parse failure. */
		if (node_cache[cfg.grouphash] && length(node_cache[cfg.grouphash]) === 0)
			return null;

		if (!node_cache[cfg.grouphash]?.[cfg['.name']]) {
			uci.delete(uciconfig, cfg['.name']);
			removed++;
			changed = true;

			log(sprintf('Removing node: %s.', cfg.label || cfg['name']));
		} else {
			const fresh_node = node_cache[cfg.grouphash][cfg['.name']];
			map(uniq([...keys(cfg), ...keys(fresh_node)]), (v) => {
				if (substr(v, 0, 1) === '.')
					return null;

				if (v in node_cache[cfg.grouphash][cfg['.name']]) {
					const fresh = node_cache[cfg.grouphash][cfg['.name']][v];
					const current = uci.get(uciconfig, cfg['.name'], v);
					if (type(fresh) === 'array' ? (sprintf('%J', current || []) !== sprintf('%J', fresh))
					    : (current !== sprintf('%s', fresh))) {
						uci.set(uciconfig, cfg['.name'], v, fresh);
						changed = true;
					}
				} else {
					uci.delete(uciconfig, cfg['.name'], v);
					changed = true;
				}
			});
			node_cache[cfg.grouphash][cfg['.name']].isExisting = true;
		}
	});
	for (let nodes in node_result)
		map(nodes, (node) => {
			if (node.isExisting)
				return null;

			const nameHash = md5(node.grouphash + node.label);
			uci.set(uciconfig, nameHash, 'node');
			map(keys(node), (v) => uci.set(uciconfig, nameHash, v, node[v]));

			added++;
			changed = true;
			log(sprintf('Adding node: %s.', node.label));
		});

	let need_restart = changed;

	uci.foreach(uciconfig, 'routing_node', (cfg) => {
		if (!(cfg.node in ['urltest', 'selector']))
			return null;

		const list_option = cfg.node + '_nodes';
		if (isEmpty(cfg[list_option]))
			return null;

		const cleaned_nodes = filter(cfg[list_option], (v) => {
			if (v in ['all-nodes', 'direct-out', 'block-out'])
				return true;
			if (substr(v, 0, 4) === 'sub_') {
				const sub_hash = substr(v, 4);
				for (let suburl in subscription_urls) {
					if (md5(replace(suburl, /#.*$/, '')) === sub_hash)
						return true;
				}
				log(sprintf('Routing node %s: subscription %s is gone, removing from %s list.', cfg['.name'], sub_hash, cfg.node));
				return false;
			}
			return !!uci.get(uciconfig, v);
		});
		if (length(cleaned_nodes) !== length(cfg[list_option])) {
			uci.set(uciconfig, cfg['.name'], list_option, cleaned_nodes);
			need_restart = true;

			log(sprintf('Routing node %s: removed gone nodes from %s list.', cfg['.name'], cfg.node));
		}
	});

	uci.commit(uciconfig);

	if (need_restart) {
		log('Restarting service...');
		init_action('homeproxy', 'stop');
		init_action('homeproxy', 'start');
	}

	log(sprintf('%s nodes added, %s removed.', added, removed));
	log('Successfully updated subscriptions.');
	return true;
}

if (!isEmpty(subscription_urls)) {
	let success = false;
	try {
		success = main();
	} catch(e) {
		log(sprintf('[FATAL ERROR] %s: %s', e.type, e.message));
	}

	update_lock.close();
	if (!success) {
		warn('Failed to update subscriptions. Check the HomeProxy log.\n');
		exit(1);
	}
}
