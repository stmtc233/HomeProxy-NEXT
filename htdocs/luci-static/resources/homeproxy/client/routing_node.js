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
'require tools.widgets as widgets';

return baseclass.extend({
	render(s, ctx) {
		const { uciconfig, proxy_nodes, urltest_choices } = ctx;
		let o, ss, so;

		s.tab('routing_node', _('Routing Nodes'));
		o = s.taboption('routing_node', form.SectionValue, '_routing_node', form.GridSection, 'routing_node');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		ss.addremove = true;
		ss.rowcolors = true;
		ss.sortable = true;
		ss.nodescriptions = true;
		ss.modaltitle = L.bind(hp.loadModalTitle, this, _('Routing node'), _('Add a routing node'), uciconfig);
		ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, uciconfig);
		ss.renderSectionAdd = L.bind(hp.renderSectionAdd, this, ss);

		so = ss.option(form.Value, 'label', _('Label'));
		so.load = L.bind(hp.loadDefaultLabel, this, uciconfig);
		so.validate = L.bind(hp.validateUniqueValue, this, uciconfig, 'routing_node', 'label');
		so.modalonly = true;

		so = ss.option(form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.option(form.ListValue, 'node', _('Node'),
			_('Outbound node'));
		so.value('urltest', _('URLTest'));
		for (let i in proxy_nodes)
			so.value(i, proxy_nodes[i]);
		so.validate = L.bind(hp.validateUniqueValue, this, uciconfig, 'routing_node', 'node');
		so.editable = true;

		so = ss.option(form.ListValue, 'domain_resolver', _('Domain resolver'),
			_('For resolving domain name in the server address.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('', _('Default'));
			this.value('default-dns', _('Default DNS (issued by WAN)'));
			this.value('system-dns', _('System DNS'));
			uci.sections(uciconfig, 'dns_server', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.depends({'node': 'urltest', '!reverse': true});
		so.modalonly = true;

		so = ss.option(form.ListValue, 'domain_strategy', _('Domain strategy'),
			_('The domain strategy for resolving the domain name in the address.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);
		so.depends({'node': 'urltest', '!reverse': true});
		so.modalonly = true;

		so = ss.option(widgets.DeviceSelect, 'bind_interface', _('Bind interface'),
			_('The network interface to bind to.'));
		so.multiple = false;
		so.noaliases = true;
		so.depends({'outbound': '', 'node': /^((?!urltest$).)+$/});
		so.modalonly = true;

		so = ss.option(form.ListValue, 'outbound', _('Outbound'),
			_('The tag of the upstream outbound.<br/>Other dial fields will be ignored when enabled.'));
		so.renderWidget = function(section_id, option_index, cfgvalue) {
			let choices = { '': _('Direct') };
			let sort = [''];

			uci.sections(uciconfig, 'routing_node', (res) => {
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
				return _('Direct');
			let target = uci.get(uciconfig, val);
			return target ? (target.label || target['.name']) : val;
		};
		so.validate = function(section_id, value) {
			if (section_id && value) {
				let node = this.section.formvalue(section_id, 'node');
				let node_gh = uci.get(uciconfig, node, 'grouphash');

				let conflict = false;
				uci.sections(uciconfig, 'routing_node', (res) => {
					if (res['.name'] !== section_id) {
						let in_urltest = res.urltest_nodes?.includes(node) || (node_gh && res.urltest_nodes?.includes('sub_' + node_gh));
						if (res.outbound === section_id && res['.name'] == value)
							conflict = true;
						else if (res.node === 'urltest' && in_urltest && res['.name'] == value)
							conflict = true;
					}
				});
				if (conflict)
					return _('Recursive outbound detected!');
			}

			return true;
		}
		so.depends({'node': 'urltest', '!reverse': true});
		so.editable = true;

		so = ss.option(hp.CBIStaticList, 'urltest_nodes', _('URLTest nodes'),
			_('List of nodes to test.'));
		for (let i in urltest_choices)
			so.value(i, urltest_choices[i]);
		so.depends('node', 'urltest');
		so.validate = function(section_id) {
			let value = this.section.formvalue(section_id, 'urltest_nodes');
			if (section_id && !value.length)
				return _('Expecting: %s').format(_('non-empty value'));

			return true;
		}
		so.modalonly = true;

		so = ss.option(form.Value, 'urltest_url', _('Test URL'),
			_('The URL to test.'));
		so.placeholder = 'https://www.gstatic.com/generate_204';
		so.default = 'https://www.gstatic.com/generate_204';
		so.validate = function(section_id, value) {
			if (section_id && value) {
				try {
					let url = new URL(value);
					if (!url.hostname)
						return _('Expecting: %s').format(_('valid URL'));
				}
				catch(e) {
					return _('Expecting: %s').format(_('valid URL'));
				}
			}

			return true;
		}
		so.depends('node', 'urltest');
		so.modalonly = true;

		so = ss.option(form.Value, 'urltest_interval', _('Test interval'),
			_('The test interval in seconds.'));
		so.datatype = 'uinteger';
		so.placeholder = '180';
		so.default = '180';
		so.validate = function(section_id, value) {
			if (section_id && value) {
				let idle_timeout = this.section.formvalue(section_id, 'urltest_idle_timeout') || '1800';
				if (parseInt(value) > parseInt(idle_timeout))
					return _('Test interval must be less or equal than idle timeout.');
			}

			return true;
		}
		so.depends('node', 'urltest');
		so.modalonly = true;

		so = ss.option(form.Value, 'urltest_tolerance', _('Test tolerance'),
			_('The test tolerance in milliseconds.'));
		so.datatype = 'uinteger';
		so.placeholder = '50';
		so.default = '50';
		so.depends('node', 'urltest');
		so.modalonly = true;

		so = ss.option(form.Value, 'urltest_idle_timeout', _('Idle timeout'),
			_('The idle timeout in seconds.'));
		so.datatype = 'uinteger';
		so.placeholder = '1800';
		so.default = '1800';
		so.depends('node', 'urltest');
		so.modalonly = true;

		so = ss.option(form.Flag, 'urltest_interrupt_exist_connections', _('Interrupt existing connections'),
			_('Interrupt existing connections when the selected outbound has changed.'));
		so.depends('node', 'urltest');
		so.modalonly = true;
	}
});
