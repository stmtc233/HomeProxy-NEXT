/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import {
	isEmpty, strToBool, strToInt, strToTime,
	buildTLSObject, buildTransportObject, buildHysteria2Realm
} from '../homeproxy.uc';

import { parse_port } from './common.uc';
import { uciconfig, ucinode, uciroutingnode } from './context.uc';

const BUILTIN_OUTBOUNDS = ['direct-out', 'block-out'];

function generate_endpoint(ctx, node) {
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	const endpoint = {
		type: node.type,
		tag: ctx.node_tag(node['.name']),
		address: node.wireguard_local_address,
		mtu: strToInt(node.wireguard_mtu),
		private_key: node.wireguard_private_key,
		peers: (node.type === 'wireguard') ? [
			{
				address: node.address,
				port: strToInt(node.port),
				allowed_ips: [
					'0.0.0.0/0',
					'::/0'
				],
				persistent_keepalive_interval: strToInt(node.wireguard_persistent_keepalive_interval),
				public_key: node.wireguard_peer_public_key,
				pre_shared_key: node.wireguard_pre_shared_key,
				reserved: parse_port(node.wireguard_reserved),
			}
		] : null,
		system: (node.type === 'wireguard') ? false : null,
		tcp_fast_open: strToBool(node.tcp_fast_open),
		tcp_multi_path: strToBool(node.tcp_multi_path),
		udp_fragment: strToBool(node.udp_fragment),
		udp_mapping: !isEmpty(ctx.udp_mapping) ? ctx.udp_mapping : null,
		udp_filtering: !isEmpty(ctx.udp_filtering) ? ctx.udp_filtering : null,
		udp_nat_max: ctx.udp_nat_max
	};

	return endpoint;
}

function generate_outbound(ctx, node) {
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	/* a realm replaces server, server_port and server_ports */
	const realm = buildHysteria2Realm(node);

	const outbound = {
		type: node.type,
		tag: ctx.node_tag(node['.name']),
		routing_mark: strToInt(ctx.self_mark),

		server: realm ? null : node.address,
		server_port: realm ? null : strToInt(node.port),
		server_ports: realm ? null : node.hysteria_hopping_port,
		realm: realm,

		username: (node.type !== 'ssh') ? node.username : null,
		user: (node.type === 'ssh') ? node.username : null,
		password: (node.type !== 'snell') ? node.password : null,
		psk: (node.type === 'snell') ? node.password : null,
		userkey: (node.type === 'snell') ? node.snell_userkey : null,
		reuse: (node.type === 'snell') ? strToBool(node.snell_reuse) : null,
		obfs_mode: (node.type === 'snell') ? (node.snell_obfs_mode || null) : null,
		obfs_host: (node.type === 'snell') ? (node.snell_obfs_host || null) : null,
		mode: (node.type === 'snell') ? (node.snell_mode || null) : null,

		proxy_protocol: strToInt(node.proxy_protocol),
		idle_session_check_interval: strToTime(node.anytls_idle_session_check_interval),
		idle_session_timeout: strToTime(node.anytls_idle_session_timeout),
		min_idle_session: strToInt(node.anytls_min_idle_session),
		hop_interval: realm ? null : strToTime(node.hysteria_hop_interval),
		hop_interval_max: realm ? null : strToTime(node.hysteria_hop_interval_max),
		up_mbps: strToInt(node.hysteria_up_mbps),
		down_mbps: strToInt(node.hysteria_down_mbps),
		obfs: node.hysteria_obfs_type ? {
			type: node.hysteria_obfs_type,
			password: node.hysteria_obfs_password,
			min_packet_size: strToInt(node.hysteria_obfs_min_packet_size),
			max_packet_size: strToInt(node.hysteria_obfs_max_packet_size)
		} : node.hysteria_obfs_password,
		auth: (node.hysteria_auth_type === 'base64') ? node.hysteria_auth_payload : null,
		auth_str: (node.hysteria_auth_type === 'string') ? node.hysteria_auth_payload : null,
		bbr_profile: (node.type === 'hysteria2') ? (node.hysteria_bbr_profile || null) : null,
		disable_chrome_parrot: (node.type === 'hysteria2' && node.hysteria_disable_chrome_parrot === '1') ? true : null,
		method: node.shadowsocks_encrypt_method,
		plugin: node.shadowsocks_plugin,
		plugin_opts: node.shadowsocks_plugin_opts,
		version: (node.type === 'shadowtls') ? strToInt(node.shadowtls_version) : ((node.type === 'socks') ? node.socks_version : ((node.type === 'snell') ? (strToInt(node.snell_version) || 4) : null)),
		client_version: node.ssh_client_version,
		host_key: node.ssh_host_key,
		host_key_algorithms: node.ssh_host_key_algo,
		private_key: node.ssh_priv_key,
		private_key_passphrase: node.ssh_priv_key_pp,
		uuid: node.uuid,
		congestion_control: node.tuic_congestion_control,
		udp_relay_mode: node.tuic_udp_relay_mode,
		udp_over_stream: strToBool(node.tuic_udp_over_stream),
		zero_rtt_handshake: strToBool(node.tuic_enable_zero_rtt),
		heartbeat: strToTime(node.tuic_heartbeat),
		flow: node.vless_flow,
		alter_id: strToInt(node.vmess_alterid),
		security: node.vmess_encrypt,
		global_padding: strToBool(node.vmess_global_padding),
		authenticated_length: strToBool(node.vmess_authenticated_length),
		packet_encoding: node.packet_encoding,

		multiplex: (node.multiplex === '1') ? {
			enabled: true,
			protocol: node.multiplex_protocol,
			max_connections: strToInt(node.multiplex_max_connections),
			min_streams: strToInt(node.multiplex_min_streams),
			max_streams: strToInt(node.multiplex_max_streams),
			padding: strToBool(node.multiplex_padding),
			brutal: (node.multiplex_brutal === '1') ? {
				enabled: true,
				up_mbps: strToInt(node.multiplex_brutal_up),
				down_mbps: strToInt(node.multiplex_brutal_down)
			} : null
		} : null,
		tls: buildTLSObject(node, false),
		transport: buildTransportObject(node, false),
		udp_over_tcp: (node.udp_over_tcp === '1') ? {
			enabled: true,
			version: strToInt(node.udp_over_tcp_version)
		} : null,
		tcp_fast_open: strToBool(node.tcp_fast_open),
		tcp_multi_path: strToBool(node.tcp_multi_path),
		udp_fragment: strToBool(node.udp_fragment)
	};

	if (node.type === 'direct' && (!isEmpty(node.override_address) || !isEmpty(node.override_port)))
		ctx.direct_overrides[node['.name']] = {
			override_address: node.override_address,
			override_port: strToInt(node.override_port)
		};

	return outbound;
}

function expand_urltest_nodes(ctx, nodes) {
	const uci = ctx.uci;
	let expanded = [];
	for (let item in (nodes || [])) {
		if (substr(item, 0, 4) === 'sub_') {
			const group_hash = substr(item, 4);
			uci.foreach(uciconfig, ucinode, (node) => {
				if (node.grouphash === group_hash) {
					if (!~index(expanded, node['.name']))
						push(expanded, node['.name']);
				}
			});
		} else if (uci.get(uciconfig, item)) {
			if (!~index(expanded, item))
				push(expanded, item);
		}
	}
	return expanded;
}

function is_routing_node(ctx, name) {
	return ctx.uci.get_all(uciconfig, name)?.['.type'] === uciroutingnode;
}

function selector_member_tag(ctx, item) {
	if (item in BUILTIN_OUTBOUNDS)
		return item;

	return is_routing_node(ctx, item) ? ctx.get_outbound(item) : ctx.node_tag(item);
}

/* sing-box check does not start the outbounds, so it lets a selector loop through */
function check_selector_loop(ctx, name, path) {
	if (name in path)
		die(sprintf("Selector loop %s, please check your configuration.",
			join(' -> ', map([...path, name], (n) => ctx.node_tag(n)))));

	const cfg = ctx.uci.get_all(uciconfig, name);
	if (cfg?.['.type'] !== uciroutingnode || cfg.node !== 'selector' || cfg.enabled !== '1')
		return;

	for (let item in (cfg.selector_nodes || []))
		check_selector_loop(ctx, item, [...path, name]);
}

/*
 * A selector takes nodes and whole subscriptions like urltest, plus other
 * routing nodes and the built-in outbounds. Returns the member tags and the
 * nodes that need an outbound of their own.
 */
function expand_selector(ctx, cfg) {
	const tags = [],
	      nodes = [];
	const add_tag = (tag) => {
		if (!~index(tags, tag))
			push(tags, tag);
	};

	for (let item in (cfg.selector_nodes || [])) {
		if (item in BUILTIN_OUTBOUNDS) {
			add_tag(item);
		} else if (is_routing_node(ctx, item)) {
			if (ctx.uci.get(uciconfig, item, 'enabled') === '1')
				add_tag(ctx.get_outbound(item));
			else
				warn(sprintf("homeproxy: selector '%s' skips the disabled routing node '%s'.\n", cfg['.name'], item));
		} else {
			for (let node in expand_urltest_nodes(ctx, [item])) {
				if (!~index(nodes, node))
					push(nodes, node);
				add_tag(ctx.node_tag(node));
			}
		}
	}

	let default_tag = null;
	if (!isEmpty(cfg.selector_default)) {
		default_tag = selector_member_tag(ctx, cfg.selector_default);
		if (!(default_tag in tags)) {
			warn(sprintf("homeproxy: selector '%s' defaults to '%s', which is not one of its members, ignoring it.\n", cfg['.name'], default_tag));
			default_tag = null;
		}
	}

	return { tags, nodes, default_tag };
}

/* endpoints and outbounds; fills ctx.direct_overrides on the way */
export function build(ctx) {
	const uci = ctx.uci;

	const endpoints = [];
	const outbounds = [
		{
			type: 'direct',
			tag: 'direct-out',
			routing_mark: strToInt(ctx.self_mark)
		},
		{
			type: 'block',
			tag: 'block-out'
		}
	];

	let group_nodes = [],
	    routing_nodes = [];
	const add_group_nodes = (nodes) => {
		group_nodes = [...group_nodes, ...filter(nodes, (l) => !~index(group_nodes, l))];
	};

	uci.foreach(uciconfig, uciroutingnode, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		if (cfg.node === 'urltest') {
			const cfg_urltest_nodes = expand_urltest_nodes(ctx, cfg.urltest_nodes);
			push(outbounds, {
				type: 'urltest',
				tag: ctx.node_tag(cfg['.name']),
				outbounds: map(cfg_urltest_nodes, (k) => ctx.node_tag(k)),
				url: cfg.urltest_url || 'https://www.gstatic.com/generate_204',
				interval: strToTime(cfg.urltest_interval || '180s'),
				tolerance: strToInt(cfg.urltest_tolerance || '50'),
				idle_timeout: strToTime(cfg.urltest_idle_timeout || '1800s'),
				interrupt_exist_connections: strToBool(cfg.urltest_interrupt_exist_connections)
			});
			add_group_nodes(cfg_urltest_nodes);
		} else if (cfg.node === 'selector') {
			check_selector_loop(ctx, cfg['.name'], []);
			const members = expand_selector(ctx, cfg);
			push(outbounds, {
				type: 'selector',
				tag: ctx.node_tag(cfg['.name']),
				outbounds: members.tags,
				default: members.default_tag,
				interrupt_exist_connections: strToBool(cfg.selector_interrupt_exist_connections)
			});
			add_group_nodes(members.nodes);
		} else {
			const outbound = uci.get_all(uciconfig, cfg.node) || {};
			if (outbound.type === 'wireguard') {
				push(endpoints, generate_endpoint(ctx, outbound));
				endpoints[length(endpoints)-1].bind_interface = cfg.bind_interface;
				endpoints[length(endpoints)-1].detour = ctx.get_outbound(cfg.outbound);
				if (cfg.domain_resolver)
					endpoints[length(endpoints)-1].domain_resolver = {
						server: ctx.get_resolver(cfg.domain_resolver),
						strategy: cfg.domain_strategy
					};
			} else {
				push(outbounds, generate_outbound(ctx, outbound));
				outbounds[length(outbounds)-1].bind_interface = cfg.bind_interface;
				outbounds[length(outbounds)-1].detour = ctx.get_outbound(cfg.outbound);
				if (cfg.domain_resolver)
					outbounds[length(outbounds)-1].domain_resolver = {
						server: ctx.get_resolver(cfg.domain_resolver),
						strategy: cfg.domain_strategy
					};
			}
			push(routing_nodes, cfg.node);
		}
	});

	for (let i in filter(group_nodes, (l) => !~index(routing_nodes, l))) {
		const group_node = uci.get_all(uciconfig, i) || {};
		if (group_node.type === 'wireguard')
			push(endpoints, generate_endpoint(ctx, group_node));
		else
			push(outbounds, generate_outbound(ctx, group_node));
	}

	return {
		endpoints: isEmpty(endpoints) ? null : endpoints,
		outbounds: outbounds
	};
};
