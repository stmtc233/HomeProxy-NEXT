/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';
'require uci';
'require ui';

'require homeproxy as hp';
'require homeproxy.client.common as common';
'require tools.widgets as widgets';

return baseclass.extend({
	render(s, ctx) {
		const { uciconfig } = ctx;
		let o, ss, so;

		s.tab('dns_server', _('DNS Servers'));
		o = s.taboption('dns_server', form.SectionValue, '_dns_server', form.GridSection, 'dns_server');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		ss.addremove = true;
		ss.rowcolors = true;
		ss.sortable = true;
		ss.nodescriptions = true;
		ss.modaltitle = L.bind(hp.loadModalTitle, this, _('DNS server'), _('Add a DNS server'), uciconfig);
		ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, uciconfig);
		ss.renderSectionAdd = L.bind(hp.renderSectionAdd, this, ss);

		so = ss.option(form.Value, 'label', _('Label'));
		so.load = L.bind(hp.loadDefaultLabel, this, uciconfig);
		so.validate = L.bind(hp.validateUniqueValue, this, uciconfig, 'dns_server', 'label');
		so.modalonly = true;

		so = ss.option(form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.option(form.ListValue, 'type', _('Type'));
		so.value('udp', _('UDP'));
		so.value('tcp', _('TCP'));
		so.value('tls', _('TLS'));
		so.value('https', _('HTTPS'));
		so.value('h3', _('HTTP/3'));
		so.value('quic', _('QUIC'));
		so.value('dhcp', _('DHCP'));
		so.value('hosts', _('Hosts'));
		so.default = 'udp';
		so.rmempty = false;

		const dns_remote_types = ['udp', 'tcp', 'tls', 'https', 'h3', 'quic'];

		so = ss.option(form.Value, 'server', _('Address'),
			_('The address of the dns server.'));
		so.datatype = 'or(hostname, ipaddr)';
		so.rmempty = false;
		for (let t of dns_remote_types)
			so.depends('type', t);

		so = ss.option(form.Value, 'server_port', _('Port'),
			_('The port of the DNS server.'));
		so.placeholder = 'auto';
		so.datatype = 'port';
		for (let t of dns_remote_types)
			so.depends('type', t);

		so = ss.option(widgets.DeviceSelect, 'dhcp_interface', _('Interface'),
			_('Interface to fetch the DNS servers from (DHCP). Leave empty to use the default interface.'));
		so.multiple = false;
		so.noaliases = true;
		so.depends('type', 'dhcp');
		so.modalonly = true;

		so = ss.option(form.DynamicList, 'hosts_path', _('Hosts files'),
			_('Hosts files to read. Leave empty to use <code>/etc/hosts</code>.'));
		so.placeholder = '/etc/hosts';
		so.depends('type', 'hosts');
		so.modalonly = true;

		so = ss.option(form.DynamicList, 'hosts_predefined', _('Predefined hosts'),
			_('One entry per line in the form <code>domain ip [ip ...]</code>, e.g. <code>nas.lan 192.168.1.10</code>.'));
		so.placeholder = 'nas.lan 192.168.1.10';
		so.validate = function(section_id, value) {
			if (!section_id || !value)
				return true;

			const fields = value.trim().split(/[\s,]+/);
			if (fields.length < 2)
				return _('Expecting: %s').format(_('domain followed by at least one IP address'));
			for (let ip of fields.slice(1))
				if (!common.stubValidator.apply('ipaddr', ip))
					return _('Expecting: %s').format(_('valid IP address'));

			return true;
		};
		so.depends('type', 'hosts');
		so.modalonly = true;

		so = ss.option(form.Value, 'path', _('Path'),
			_('The path of the DNS server.'));
		so.placeholder = '/dns-query';
		so.depends('type', 'https');
		so.depends('type', 'h3');
		so.modalonly = true;

		so = ss.option(form.DynamicList, 'headers', _('Headers'),
			_('Additional headers to be sent to the DNS server, one <code>Name: value</code> per line.'));
		so.depends('type', 'https');
		so.depends('type', 'h3');
		so.modalonly = true;

		so = ss.option(form.Value, 'tls_sni', _('TLS SNI'),
			_('Used to verify the hostname on the returned certificates.'));
		so.depends('type', 'tls');
		so.depends('type', 'https');
		so.depends('type', 'h3');
		so.depends('type', 'quic');
		so.modalonly = true;

		so = ss.option(form.ListValue, 'address_resolver', _('Address resolver'),
			_('Tag of a another server to resolve the domain name in the address. Required if address contains domain.'));
		so.renderWidget = function(section_id, option_index, cfgvalue) {
			let choices = {
				'': _('None'),
				'default-dns': _('Default DNS (issued by WAN)'),
				'system-dns': _('System DNS')
			};
			let sort = ['', 'default-dns', 'system-dns'];

			uci.sections(uciconfig, 'dns_server', (res) => {
				if (res['.name'] !== section_id && res.enabled === '1') {
					choices[res['.name']] = res.label || res['.name'];
					sort.push(res['.name']);
				}
			});

			let widget = new ui.Select((cfgvalue != null) ? cfgvalue : this.default, choices, {
				id: this.cbid(section_id),
				size: this.size,
				sort: sort,
				widget: this.widget,
				optional: this.optional,
				orientation: this.orientation,
				placeholder: this.placeholder,
				validate: L.bind(this.validate, this, section_id),
				disabled: (this.readonly != null) ? this.readonly : this.map.readonly
			});

			return widget.render();
		};
		so.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id);
			if (!val)
				return _('None');
			if (val === 'default-dns')
				return _('Default DNS (issued by WAN)');
			if (val === 'system-dns')
				return _('System DNS');
			let target = uci.get(uciconfig, val);
			return target ? (target.label || target['.name']) : val;
		};
		so.validate = function(section_id, value) {
			if (section_id && value) {
				let conflict = false;
				uci.sections(uciconfig, 'dns_server', (res) => {
					if (res['.name'] !== section_id)
						if (res.address_resolver === section_id && res['.name'] == value)
							conflict = true;
				});
				if (conflict)
					return _('Recursive resolver detected!');
			}

			return true;
		}
		for (let t of dns_remote_types)
			so.depends('type', t);
		so.modalonly = true;

		so = ss.option(form.ListValue, 'address_strategy', _('Address strategy'),
			_('The domain strategy for resolving the domain name in the address.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);
		so.depends({'address_resolver': '', '!reverse': true});
		so.modalonly = true;

		so = ss.option(form.ListValue, 'outbound', _('Outbound'),
			_('Tag of an outbound for connecting to the dns server.'));
		so.default = 'direct-out';
		so.rmempty = false;
		so.retain = true;
		for (let t of [...dns_remote_types, 'dhcp'])
			so.depends('type', t);
		so.renderWidget = function(section_id, option_index, cfgvalue) {
			let choices = { 'direct-out': _('Direct') };
			let sort = ['direct-out'];

			uci.sections(uciconfig, 'routing_node', (res) => {
				if (res.enabled === '1') {
					choices[res['.name']] = res.label || res['.name'];
					sort.push(res['.name']);
				}
			});

			let widget = new ui.Select((cfgvalue != null) ? cfgvalue : this.default, choices, {
				id: this.cbid(section_id),
				size: this.size,
				sort: sort,
				widget: this.widget,
				optional: this.optional,
				orientation: this.orientation,
				placeholder: this.placeholder,
				validate: L.bind(this.validate, this, section_id),
				disabled: (this.readonly != null) ? this.readonly : this.map.readonly
			});

			return widget.render();
		};
		so.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id);
			if (!val || val === 'direct-out')
				return _('Direct');
			let target = uci.get(uciconfig, val);
			return target ? (target.label || target['.name']) : val;
		};
		so.write = function(section_id, formvalue) {
			let res = this.super('write', section_id, formvalue);
			if (this.map && this.map.parent) {
				let node = this.map.parent.findElement('id', this.cbid(section_id));
				if (node) {
					let select = node.querySelector('select');
					if (select) {
						select.value = formvalue;
						select.dispatchEvent(new Event('change'));
					}
				}
			}
			return res;
		};
	}
});
