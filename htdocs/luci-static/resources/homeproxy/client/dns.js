/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';
'require uci';

'require homeproxy as hp';

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
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('default-dns', _('Default DNS (issued by WAN)'));
			this.value('system-dns', _('System DNS'));
			uci.sections(uciconfig, 'dns_server', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.default = 'default-dns';
		so.rmempty = false;

		so = ss.option(form.Flag, 'disable_cache', _('Disable DNS cache'));

		so = ss.option(form.Flag, 'disable_cache_expire', _('Disable cache expire'));
		so.depends('disable_cache', '0');

		so = ss.option(form.Value, 'client_subnet', _('EDNS Client subnet'),
			_('Append a <code>edns0-subnet</code> OPT extra record with the specified IP prefix to every query by default.<br/>' +
			'If value is an IP address instead of prefix, <code>/32</code> or <code>/128</code> will be appended automatically.'));
		so.datatype = 'or(cidr, ipaddr)';

		so = ss.option(form.Flag, 'optimistic_cache', _('Optimistic DNS cache'),
			_('Return expired cache immediately and refresh in background (sing-box 1.14).'));
		so.depends('disable_cache', '0');
		so.depends('disable_cache_expire', '0');
		so.rmempty = false;

		so = ss.option(form.Value, 'optimistic_timeout', _('Optimistic cache timeout'),
			_('Max time an expired entry may be served. Examples: 3d, 1h.'));

		so = ss.option(form.Value, 'dns_timeout', _('DNS query timeout'),
			_('Default timeout per DNS query in seconds (sing-box default: 10).'));
		so.datatype = 'uinteger';

		so = ss.option(form.Flag, 'cache_file_store_dns', _('Store DNS cache'),
			_('Persist DNS cache across restarts (sing-box 1.14, replaces Store RDRC).'));
		so.depends('disable_cache', '0');
		so.rmempty = false;
	}
});
