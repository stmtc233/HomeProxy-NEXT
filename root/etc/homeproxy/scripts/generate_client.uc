#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { access, writefile } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';

import { isEmpty, removeBlankAttrs, RUN_DIR } from 'homeproxy';

import { load, uciconfig } from 'client.context';
import * as dns from 'client.dns';
import * as inbounds from 'client.inbounds';
import * as outbounds from 'client.outbounds';
import * as route from 'client.route';

const uci = cursor();
uci.load(uciconfig);

const ctx = load(uci, connect());

const config = {};

config.log = {
	disabled: false,
	level: ctx.log_level,
	output: RUN_DIR + '/sing-box-c.log',
	timestamp: true
};

if (!isEmpty(ctx.ntp_server))
	config.ntp = {
		enabled: true,
		server: ctx.ntp_server,
		detour: 'direct-out',
		domain_resolver: 'default-dns',
	};

config.dns = dns.build(ctx);
config.inbounds = inbounds.build(ctx);

/* the order matters: route reads the direct-node overrides the outbounds record */
const out = outbounds.build(ctx);
config.endpoints = out.endpoints;
config.outbounds = out.outbounds;
config.route = route.build(ctx);

if (ctx.dashboard_enabled === '1') {
	const listen_match = match(ctx.dashboard_listen, /^\[?([^\]]*)\]?:([0-9]+)$/);

	config.services = [{
		type: 'api',
		listen: listen_match ? listen_match[1] : '0.0.0.0',
		listen_port: listen_match ? int(listen_match[2]) : 9090,
		secret: ctx.dashboard_secret,
		dashboard: {
			enabled: true,
			path: RUN_DIR + '/dashboard/web',
			download_url: ctx.dashboard_url,
			http_client: ctx.http_client_for(isEmpty(ctx.main_node) || ctx.main_node === 'nil' ? null : 'main-out')
		}
	}];
}

if (length(ctx.http_clients))
	config.http_clients = ctx.http_clients;

if (ctx.routing_mode in ['bypass_mainland_china', 'custom']) {
	config.experimental = {
		cache_file: {
			enabled: true,
			path: '/etc/homeproxy/cache.db',
			store_dns: (ctx.dns_store_dns === '1') ? true : null
		}
	};
}

config['$schema'] = 'https://sing-box.sagernet.org/schema.json';

system('mkdir -p ' + RUN_DIR);
const client_tmp = RUN_DIR + '/sing-box-c.json.tmp';
writefile(client_tmp, sprintf('%.J\n', removeBlankAttrs(config)));
if (system('/usr/bin/sing-box check --config ' + client_tmp) !== 0) {
	system('rm -f ' + client_tmp);
	exit(1);
}
/*
 * Overwrite an existing config in place: the jailed sing-box has the file
 * bind-mounted, so after a rename a reload by SIGHUP would re-read the old
 * inode. In-place also keeps the owner the jailed process reads it as.
 */
const client_conf = RUN_DIR + '/sing-box-c.json';
if (access(client_conf))
	system(`cat ${client_tmp} > ${client_conf} && rm -f ${client_tmp}`);
else
	system(`mv -f ${client_tmp} ${client_conf}`);
system('chmod 600 ' + client_conf);
