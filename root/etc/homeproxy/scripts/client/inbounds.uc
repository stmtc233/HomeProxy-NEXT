/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { isEmpty, strToBool, strToInt, strToTime } from '../homeproxy.uc';

export function build(ctx) {
	const proxy_mode = ctx.proxy_mode;
	const inbounds = [];

	push(inbounds, {
		type: 'direct',
		tag: 'dns-in',
		listen: '127.0.0.1',
		listen_port: int(ctx.dns_port)
	});

	push(inbounds, {
		type: 'mixed',
		tag: 'mixed-in',
		listen: '::',
		listen_port: int(ctx.mixed_port),
		udp_timeout: strToTime(ctx.udp_timeout),
		set_system_proxy: false
	});

	if (match(proxy_mode, /redirect/))
		push(inbounds, {
			type: 'redirect',
			tag: 'redirect-in',

			listen: '::',
			listen_port: int(ctx.redirect_port)
		});
	if (match(proxy_mode, /tproxy/))
		push(inbounds, {
			type: 'tproxy',
			tag: 'tproxy-in',

			listen: '::',
			listen_port: int(ctx.tproxy_port),
			network: 'udp',
			udp_timeout: strToTime(ctx.udp_timeout),
			udp_mapping: !isEmpty(ctx.udp_mapping) ? ctx.udp_mapping : null,
			udp_filtering: !isEmpty(ctx.udp_filtering) ? ctx.udp_filtering : null,
			udp_nat_max: ctx.udp_nat_max,
		});
	if (match(proxy_mode, /tun/))
		push(inbounds, {
			type: 'tun',
			tag: 'tun-in',

			interface_name: ctx.tun_name,
			address: (ctx.ipv6_support === '1') ? [ctx.tun_addr4, ctx.tun_addr6] : [ctx.tun_addr4],
			mtu: strToInt(ctx.tun_mtu),
			auto_route: false,
			endpoint_independent_nat: strToBool(ctx.endpoint_independent_nat),
			udp_timeout: strToTime(ctx.udp_timeout),
			dns_mode: !isEmpty(ctx.tun_dns_mode) ? ctx.tun_dns_mode : null,
			dns_address: !isEmpty(ctx.tun_dns_address) ? ctx.tun_dns_address : null,
			udp_mapping: !isEmpty(ctx.udp_mapping) ? ctx.udp_mapping : null,
			udp_filtering: !isEmpty(ctx.udp_filtering) ? ctx.udp_filtering : null,
			udp_nat_max: ctx.udp_nat_max,
			stack: ctx.tcpip_stack,
		});

	return inbounds;
};
