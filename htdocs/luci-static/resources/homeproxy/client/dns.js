/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';

'require homeproxy as hp';
'require homeproxy.client.common as common';

return baseclass.extend({
	render(s, ctx) {
		const { uciconfig } = ctx;
		let o, ss, so;

		s.tab('dns', _('DNS Settings'));
		o = s.taboption('dns', form.SectionValue, '_dns', form.NamedSection, 'dns', 'homeproxy');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		so = ss.option(form.ListValue, 'default_strategy', _('Default DNS strategy'),
			_('The DNS strategy for resolving the domain name in the address.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);

		so = ss.option(form.ListValue, 'default_server', _('Default DNS server'));
		so.load = common.loadSectionChoices(uciconfig, 'dns_server', common.builtinDnsServers());
		so.default = 'default-dns';
		so.rmempty = false;

		so = ss.option(form.Flag, 'disable_cache', _('Disable DNS cache'));

		so = ss.option(form.Flag, 'disable_cache_expire', _('Disable cache expire'));
		so.depends('disable_cache', '0');

		so = ss.option(form.Value, 'client_subnet', _('EDNS Client subnet'),
			_('Append a <code>edns0-subnet</code> OPT extra record with the specified IP prefix to every query by default.<br/>' +
			'If value is an IP address instead of prefix, <code>/32</code> or <code>/128</code> will be appended automatically.'));
		so.datatype = 'or(cidr, ipaddr)';
	}
});
