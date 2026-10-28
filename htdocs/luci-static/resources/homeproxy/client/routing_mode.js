/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 ImmortalWrt.org
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

		s.tab('routing_mode', _('Routing Modes'));
		o = s.taboption('routing_mode', form.SectionValue, '_routing_mode', form.GridSection, 'routing_mode', null,
			_('Each mode has its own routing rules and DNS rules, and its own outbound and DNS server for what none of them matches. The mode is switched in the dashboard, without a restart.'));

		ss = o.subsection;
		ss.addremove = true;
		ss.rowcolors = true;
		ss.sortable = true;
		ss.nodescriptions = true;
		ss.modaltitle = L.bind(hp.loadModalTitle, this, _('Routing mode'), _('Add a routing mode'), uciconfig);
		ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, uciconfig);
		ss.renderSectionAdd = L.bind(hp.renderSectionAdd, this, ss);

		so = ss.option(form.Value, 'label', _('Name'),
			_('The name sing-box and the dashboard show for the mode.'));
		so.load = L.bind(hp.loadDefaultLabel, this, uciconfig);
		so.validate = L.bind(hp.validateUniqueValue, this, uciconfig, 'routing_mode', 'label');
		so.modalonly = true;

		so = ss.option(form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.option(form.ListValue, 'default_outbound', _('Default outbound'),
			_('Default outbound for connections not matched by any routing rules of this mode.'));
		common.bindSectionSelect(so, uciconfig, 'routing_node', {
			'direct-out': _('Direct'),
			'block-out': _('Block')
		});
		so.default = 'direct-out';
		so.rmempty = false;
		so.editable = true;
		so.write = common.writeAndSyncSelect;

		so = ss.option(form.ListValue, 'default_server', _('Default DNS server'),
			_('DNS server for queries not matched by any DNS rules of this mode.'));
		common.bindSectionSelect(so, uciconfig, 'dns_server', common.builtinDnsServers());
		so.default = 'default-dns';
		so.rmempty = false;
		so.editable = true;
		so.write = common.writeAndSyncSelect;
	}
});
