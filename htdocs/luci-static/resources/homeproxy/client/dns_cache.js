/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';

return baseclass.extend({
	render(s, ctx) {
		let o, ss, so;

		s.tab('dns_cache', _('DNS Cache (1.14)'));
		o = s.taboption('dns_cache', form.SectionValue, '_dns_cache', form.NamedSection, 'dns', 'homeproxy');
		o.depends({'routing_mode': 'custom', '!reverse': true});
		ss = o.subsection;

		so = ss.option(form.Flag, 'optimistic_cache', _('Optimistic DNS cache'),
			_('Return expired cache immediately and refresh in background (sing-box 1.14).'));
		so.rmempty = false;

		so = ss.option(form.Value, 'optimistic_timeout', _('Optimistic cache timeout'),
			_('Max time an expired entry may be served. Examples: 3d, 1h.'));

		so = ss.option(form.Value, 'dns_timeout', _('DNS query timeout'),
			_('Default timeout per DNS query in seconds (sing-box default: 10).'));
		so.datatype = 'uinteger';

		so = ss.option(form.Flag, 'cache_file_store_dns', _('Store DNS cache'),
			_('Persist DNS cache across restarts (replaces Store RDRC).'));
		so.rmempty = false;
	}
});
