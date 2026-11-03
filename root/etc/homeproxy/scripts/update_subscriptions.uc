#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 *
 * Usage: update_subscriptions.uc [run-id]
 *
 * Downloads every subscription, then merges the nodes into UCI in one go and
 * reloads the service only when something changed. The service keeps running
 * meanwhile, so the downloads use the current routing. Progress goes to
 * SUBSCRIPTION_STATUS (see homeproxy.uc), which the node page polls: the
 * page starts this script in the background through rpcd, as a download can
 * take longer than any RPC timeout.
 */

'use strict';

import { md5 } from 'digest';
import { open, readlink, rename, writefile } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';

import {
	wGETVerbose, decodeBase64Str, getTime, isEmpty, DEFAULTS, RUN_DIR, SUBSCRIPTION_STATUS
} from 'homeproxy';

import { parse_uri } from 'parse_uri';

const INIT_SCRIPT = '/etc/init.d/homeproxy';

const uciconfig = 'homeproxy',
      ucinode = 'node',
      ucisource = 'subscription_source',
      ucisubscription = 'subscription';

const FIXED_MEMBERS = ['all-nodes', 'direct-out', 'block-out'];

function log(...args) {
	const logfile = open(`${RUN_DIR}/homeproxy.log`, 'a');
	logfile.write(`${getTime()} [SUBSCRIBE] ${join(' ', args)}\n`);
	logfile.close();
}

function strip_fragment(url) {
	return replace(url, /#.*$/, '');
}

/* query strings usually carry the token */
function redact(url) {
	return replace(url, /[?#].*$/, '');
}

system(`mkdir -p ${RUN_DIR}`);
/* Keep the inode: unlinking a flock file can let two updaters run at once. */
const update_lock = open(RUN_DIR + '/update_subscriptions.flock', 'a');

if (!update_lock || !update_lock.lock('xn')) {
	warn('Another subscription update is running.\n');
	exit(2);
}

const status = {
	id: (type(ARGV[0]) === 'string' && match(ARGV[0], /^[A-Za-z0-9-]{1,64}$/)) ? ARGV[0] : `${time()}`,
	pid: int(readlink('/proc/self')),
	state: 'running',
	stage: 'fetching',
	started: time(),
	subscriptions: {}
};

function save_status() {
	const tmp = SUBSCRIPTION_STATUS + '.tmp';
	if (writefile(tmp, sprintf('%J\n', status)) != null)
		rename(tmp, SUBSCRIPTION_STATUS);
}

function finish(state, extra) {
	status.state = state;
	status.finished = time();
	for (let k, v in (extra || {}))
		status[k] = v;
	save_status();
	update_lock.close();
}

function read_settings() {
	const uci = cursor();
	uci.load(uciconfig);

	const get = (option) => uci.get(uciconfig, ucisubscription, option);
	/*
	 * The section name is the subscription's id: the grouphash of its nodes
	 * and the sub_<id> of the groups. One without URL keeps both.
	 */
	const subs = [], known = {};
	uci.foreach(uciconfig, ucisource, (cfg) => {
		known[cfg['.name']] = true;
		if (isEmpty(cfg.url))
			return;
		const url = strip_fragment(cfg.url);
		push(subs, { url, hash: cfg['.name'], shown_url: redact(url) });
	});

	return {
		subs,
		known,
		allow_insecure: get('allow_insecure') || '0',
		filter_mode: get('filter_nodes') || DEFAULTS.subscription.filter_nodes,
		filter_keywords: get('filter_keywords') || [],
		packet_encoding: get('packet_encoding') || DEFAULTS.subscription.packet_encoding,
		user_agent: get('user_agent')
	};
}

/* true: drop the node */
function filtered_out(settings, name) {
	if (isEmpty(name) || settings.filter_mode === 'disabled' || isEmpty(settings.filter_keywords))
		return false;

	let hit = false;
	for (let keyword in settings.filter_keywords) {
		let pattern;
		try {
			pattern = regexp(keyword);
		} catch(e) {
			log(sprintf('Skipping invalid filter keyword regex: %s.', keyword));
			continue;
		}
		if (match(name, pattern))
			hit = true;
	}

	return (settings.filter_mode === 'whitelist') ? !hit : hit;
}

function valid_port(port) {
	return match(port, /^\d{1,5}$/) != null && int(port) > 0 && int(port) <= 65535;
}

function node_problem(cfg) {
	if (isEmpty(cfg.address) || isEmpty(cfg.port))
		return 'missing address or port';
	if (!valid_port(cfg.port))
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

/*
 * The values as UCI stores them: strings, lists of strings, nothing empty.
 * Comparing against UCI then only reports real changes.
 */
function to_uci(config) {
	const res = {};
	for (let k, v in config) {
		if (type(v) === 'array') {
			v = map(filter(v, (x) => x != null && x !== ''), (x) => `${x}`);
			if (length(v))
				res[k] = v;
		} else if (v != null && v !== '')
			res[k] = `${v}`;
	}

	return res;
}

function decode_entries(content) {
	try {
		let entries = json(content);
		entries = entries.servers || entries;
		if (entries[0].server && entries[0].method)
			map(entries, (_, i) => entries[i].nodetype = 'sip008');
		return entries;
	} catch(e) {
		if (match(content, /(^|\n)[ \t]*(proxies|proxy-groups)[ \t]*:/))
			return null;

		const decoded = decodeBase64Str(content);
		return decoded ? split(trim(decoded), '\n') : [];
	}
}

/* { nodes: { <section name>: config }, order: [...] }, or { error, detail } */
function fetch_subscription(sub, settings, features) {
	const fetched = wGETVerbose(sub.url, settings.user_agent);
	if (isEmpty(fetched.content)) {
		const detail = replace(fetched.error || 'empty response', sub.url, sub.shown_url);
		log(sprintf('Failed to fetch resources from %s: %s', sub.shown_url, detail));
		return { error: 'fetch', detail };
	}

	const entries = decode_entries(fetched.content);
	if (entries == null) {
		log(sprintf('Unsupported subscription format (Clash/mihomo YAML) at %s.', sub.shown_url));
		return { error: 'format' };
	}

	const nodes = {}, order = [], seen = {};
	let skipped = 0, filtered = 0;
	for (let entry in entries) {
		if (isEmpty(entry))
			continue;

		const parsed = parse_uri(entry, features, log);
		if (isEmpty(parsed)) {
			if (skipped < 5)
				log(sprintf('Skipping unparsable entry (%s) from %s.',
					type(entry) === 'string' ? replace(entry, /:.*$/, '') : type(entry), sub.shown_url));
			skipped++;
			continue;
		}

		const config = to_uci(parsed);
		const problem = node_problem(config);
		if (problem) {
			if (skipped < 5)
				log(sprintf('Skipping invalid node %s: %s.', config.label || config.address, problem));
			skipped++;
			continue;
		}

		if (filtered_out(settings, config.label)) {
			filtered++;
			continue;
		}

		const label = config.label;
		delete config.label;
		const conf_hash = md5(sprintf('%J', config)),
		      name = md5(sub.hash + label);
		if (label != null)
			config.label = label;

		if (seen[conf_hash] || nodes[name]) {
			log(sprintf('Skipping duplicate node: %s.', label));
			continue;
		}
		seen[conf_hash] = true;

		if (config.tls === '1' && settings.allow_insecure === '1')
			config.tls_insecure = '1';
		if (config.type in ['vless', 'vmess'] && !isEmpty(settings.packet_encoding))
			config.packet_encoding = settings.packet_encoding;
		config.grouphash = sub.hash;

		nodes[name] = config;
		push(order, name);
	}

	if (skipped > 0)
		log(sprintf('%s entries skipped from %s.', skipped, sub.shown_url));
	if (filtered > 0)
		log(sprintf('%s nodes filtered out from %s.', filtered, sub.shown_url));

	if (!length(order)) {
		log(sprintf('No valid node found in %s.', sub.shown_url));
		return { error: 'no_nodes', skipped, filtered };
	}

	log(sprintf('Successfully fetched %s nodes of total %s from %s.', length(order), length(entries), sub.shown_url));
	return { nodes, order, skipped, filtered };
}

/*
 * results[hash] holds the fresh nodes of a subscription, or nothing when it
 * failed (or has no URL): those keep their nodes. Nodes of subscriptions that
 * are no longer configured go away.
 */
function merge_nodes(uci, subs, configured, results) {
	const sections = [];
	uci.foreach(uciconfig, ucinode, (cfg) => {
		if (cfg.grouphash)
			push(sections, cfg);
	});

	let added = 0, removed = 0, updated = 0;
	const present = {};
	for (let cfg in sections) {
		const name = cfg['.name'], hash = cfg.grouphash;
		if (configured[hash] && !results[hash])
			continue;

		const fresh = results[hash]?.nodes[name];
		if (!fresh) {
			uci.delete(uciconfig, name);
			removed++;
			log(sprintf('Removing node: %s.', cfg.label || name));
			continue;
		}

		present[name] = true;
		let dirty = false;
		for (let k in uniq([...keys(cfg), ...keys(fresh)])) {
			if (substr(k, 0, 1) === '.')
				continue;
			if (!(k in fresh)) {
				uci.delete(uciconfig, name, k);
				dirty = true;
			} else if (sprintf('%J', cfg[k]) !== sprintf('%J', fresh[k])) {
				uci.set(uciconfig, name, k, fresh[k]);
				dirty = true;
			}
		}
		if (dirty)
			updated++;
	}

	for (let sub in subs) {
		const res = results[sub.hash];
		for (let name in (res?.order || [])) {
			if (present[name])
				continue;

			uci.set(uciconfig, name, ucinode);
			for (let k, v in res.nodes[name])
				uci.set(uciconfig, name, k, v);
			added++;
			log(sprintf('Adding node: %s.', res.nodes[name].label));
		}
	}

	return { added, removed, updated };
}

/* drop group members that point at removed nodes or subscriptions */
function clean_groups(uci, configured) {
	const groups = [];
	uci.foreach(uciconfig, 'routing_node', (cfg) => {
		if (cfg.node in ['urltest', 'selector'] && !isEmpty(cfg[cfg.node + '_nodes']))
			push(groups, cfg);
	});

	let changed = false;
	for (let cfg in groups) {
		const option = cfg.node + '_nodes';
		const members = filter(cfg[option], (v) => {
			if (v in FIXED_MEMBERS)
				return true;
			if (substr(v, 0, 4) === 'sub_')
				return !!configured[substr(v, 4)];
			return !!uci.get(uciconfig, v);
		});
		if (length(members) !== length(cfg[option])) {
			uci.set(uciconfig, cfg['.name'], option, members);
			changed = true;
			log(sprintf('Routing node %s: removed gone nodes from %s list.', cfg['.name'], cfg.node));
		}
	}

	return changed;
}

function main() {
	const settings = read_settings();
	if (isEmpty(settings.subs)) {
		finish('done', { added: 0, removed: 0, updated: 0 });
		return true;
	}

	for (let sub in settings.subs)
		status.subscriptions[sub.hash] = { state: 'pending' };
	save_status();

	const features = connect()?.call('luci.homeproxy', 'singbox_get_features', {}) || {};
	if (isEmpty(features))
		log('Warning: Failed to query sing-box features via ubus, assuming defaults.');

	const results = {};
	let fetched = 0;
	for (let sub in settings.subs) {
		const entry = status.subscriptions[sub.hash];
		entry.state = 'fetching';
		save_status();

		const res = fetch_subscription(sub, settings, features);
		entry.skipped = res.skipped;
		entry.filtered = res.filtered;
		if (res.error) {
			entry.state = 'failed';
			entry.error = res.error;
			entry.detail = res.detail;
		} else {
			entry.state = 'done';
			entry.nodes = length(res.order);
			results[sub.hash] = res;
			fetched++;
		}
		save_status();
	}

	if (!fetched) {
		log('Failed to update subscriptions: no valid node found.');
		finish('failed', { error: 'no_nodes' });
		return false;
	}

	status.stage = 'saving';
	save_status();

	/* a fresh cursor: the downloads may have taken a while */
	const uci = cursor();
	uci.load(uciconfig);
	const counts = merge_nodes(uci, settings.subs, settings.known, results);
	const groups_changed = clean_groups(uci, settings.known);
	uci.commit(uciconfig);

	let reload_failed = false;
	if (counts.added || counts.removed || counts.updated || groups_changed) {
		status.stage = 'reloading';
		save_status();
		log('Reloading service...');
		reload_failed = (system(`${INIT_SCRIPT} reload >/dev/null 2>&1`) !== 0);
		if (reload_failed)
			log('Error: failed to reload the service, check the messages above.');
	}

	log(sprintf('%s nodes added, %s updated, %s removed.', counts.added, counts.updated, counts.removed));
	log('Successfully updated subscriptions.');
	finish('done', { ...counts, reload_failed: reload_failed });
	return true;
}

let success = false;
try {
	success = main();
} catch(e) {
	log(sprintf('[FATAL ERROR] %s: %s', e.type, e.message));
	finish('failed', { error: 'exception', detail: e.message });
}

if (!success) {
	warn('Failed to update subscriptions. Check the HomeProxy log.\n');
	exit(1);
}
