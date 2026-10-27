/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';

/*
 * The cache options of the dns section live only here: LuCI tells fields
 * apart by section and option, so a second copy in the DNS Settings tab
 * would shadow these, hiding them and saving the hidden copy's values.
 */
return baseclass.extend({
	render(s, ctx) {
		const custom = { 'homeproxy.config.routing_mode': 'custom' };
		let o, ss, so;

		s.tab('dns_cache', _('DNS Cache (1.14)'));
		o = s.taboption('dns_cache', form.SectionValue, '_dns_cache', form.NamedSection, 'dns', 'homeproxy');
		ss = o.subsection;

		/* outside the custom mode the DNS cache switches are not used */
		so = ss.option(form.Flag, 'optimistic_cache', _('Optimistic DNS cache'),
			_('Return expired cache immediately and refresh in background (sing-box 1.14).'));
		so.depends(Object.assign({ '!reverse': true }, custom));
		so.depends(Object.assign({ disable_cache: '0' }, custom));
		so.depends(Object.assign({ disable_cache_expire: '0' }, custom));
		so.rmempty = false;

		so = ss.option(form.Value, 'optimistic_timeout', _('Optimistic cache timeout'),
			_('Max time an expired entry may be served. Examples: 3d, 1h.'));

		so = ss.option(form.Value, 'dns_timeout', _('DNS query timeout'),
			_('Default timeout per DNS query in seconds (sing-box default: 10).'));
		so.datatype = 'uinteger';

		so = ss.option(form.Flag, 'cache_file_store_dns', _('Store DNS cache'),
			_('Persist DNS cache across restarts (replaces Store RDRC).'));
		so.depends(Object.assign({ '!reverse': true }, custom));
		so.depends(Object.assign({ disable_cache: '0' }, custom));
		so.rmempty = false;
	}
});
