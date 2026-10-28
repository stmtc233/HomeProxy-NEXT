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
'require homeproxy.client.common as common';
'require tools.widgets as widgets';

/* a selector may also pick other routing nodes and the built-in outbounds */
function loadSelectorChoices(uciconfig, fixed, nodes) {
	return function(section_id) {
		delete this.keylist;
		delete this.vallist;

		for (let i in fixed)
			this.value(i, fixed[i]);
		this.value('direct-out', _('Direct'));
		this.value('block-out', _('Block'));
		uci.sections(uciconfig, 'routing_node', (res) => {
			if (res['.name'] !== section_id && res.enabled === '1')
				this.value(res['.name'], String.format('[%s] %s', _('Routing node'), res.label || res['.name']));
		});
		for (let i in nodes)
			this.value(i, nodes[i]);

		return this.super('load', section_id);
	};
}

/* whether the selector members reach section_id again through nested selectors */
function selectorLoops(uciconfig, section_id, members, seen) {
	return members.some((m) => {
		if (m === section_id)
			return true;
		if (seen.includes(m))
			return false;

		let res = uci.get(uciconfig, m);
		if (!res || res['.type'] !== 'routing_node' || res.node !== 'selector')
			return false;

		return selectorLoops(uciconfig, section_id, res.selector_nodes || [], seen.concat(m));
	});
}

return baseclass.extend({
	render(s, ctx) {
		const { uciconfig, proxy_nodes, urltest_choices } = ctx;
		const group_re = /^(urltest|selector)$/;
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
		so.value('selector', _('Selector'));
		for (let i in proxy_nodes)
			so.value(i, proxy_nodes[i]);
		so.validate = L.bind(hp.validateUniqueValue, this, uciconfig, 'routing_node', 'node');
		so.editable = true;

		so = ss.option(form.ListValue, 'domain_resolver', _('Domain resolver'),
			_('For resolving domain name in the server address.'));
		so.load = common.loadSectionChoices(uciconfig, 'dns_server', Object.assign({ '': _('Default') }, common.builtinDnsServers()));
		so.depends({'node': group_re, '!reverse': true});
		so.modalonly = true;

		so = ss.option(form.ListValue, 'domain_strategy', _('Domain strategy'),
			_('The domain strategy for resolving the domain name in the address.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);
		so.depends({'node': group_re, '!reverse': true});
		so.modalonly = true;

		so = ss.option(widgets.DeviceSelect, 'bind_interface', _('Bind interface'),
			_('The network interface to bind to.'));
		so.multiple = false;
		so.noaliases = true;
		so.depends({'outbound': '', 'node': /^(?!(urltest|selector)$).+$/});
		so.modalonly = true;

		so = ss.option(form.ListValue, 'outbound', _('Outbound'),
			_('The tag of the upstream outbound.<br/>Other dial fields will be ignored when enabled.'));
		common.bindSectionSelect(so, uciconfig, 'routing_node', { '': _('Direct') }, true);
		so.validate = function(section_id, value) {
			if (section_id && value) {
				let node = this.section.formvalue(section_id, 'node');
				let node_gh = uci.get(uciconfig, node, 'grouphash');

				let conflict = false;
				uci.sections(uciconfig, 'routing_node', (res) => {
					if (res['.name'] !== section_id) {
						let members = (res.node === 'selector') ? res.selector_nodes : res.urltest_nodes;
						let in_group = members?.includes(node) || (node_gh && members?.includes('sub_' + node_gh))
							|| (res.node === 'selector' && members?.includes(section_id));
						if (res.outbound === section_id && res['.name'] == value)
							conflict = true;
						else if (group_re.test(res.node) && in_group && res['.name'] == value)
							conflict = true;
					}
				});
				if (conflict)
					return _('Recursive outbound detected!');
			}

			return true;
		}
		so.depends({'node': group_re, '!reverse': true});
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

		so = ss.option(hp.CBIStaticList, 'selector_nodes', _('Selector nodes'),
			_('Outbounds to choose from: nodes, whole subscriptions, other routing nodes, direct or block.'));
		so.load = loadSelectorChoices(uciconfig, {}, urltest_choices);
		so.depends('node', 'selector');
		so.validate = function(section_id) {
			let value = this.section.formvalue(section_id, 'selector_nodes') || [];
			if (section_id && !value.length)
				return _('Expecting: %s').format(_('non-empty value'));
			if (section_id && selectorLoops(uciconfig, section_id, value, []))
				return _('Recursive outbound detected!');

			return true;
		}
		so.modalonly = true;

		so = ss.option(form.ListValue, 'selector_default', _('Default outbound'),
			_('Used until another outbound is selected, the first one if empty. A selection is kept across restarts.'));
		so.load = loadSelectorChoices(uciconfig, { '': _('Default') }, proxy_nodes);
		so.depends('node', 'selector');
		so.validate = function(section_id, value) {
			if (section_id && value) {
				let members = this.section.formvalue(section_id, 'selector_nodes') || [];
				let node_gh = uci.get(uciconfig, value, 'grouphash');
				if (!members.includes(value) && !(node_gh && members.includes('sub_' + node_gh)))
					return _('Expecting: %s').format(_('one of the selector nodes'));
			}

			return true;
		}
		so.modalonly = true;

		so = ss.option(form.Flag, 'selector_interrupt_exist_connections', _('Interrupt existing connections'),
			_('Interrupt existing connections when the selected outbound has changed.'));
		so.depends('node', 'selector');
		so.modalonly = true;
	}
});
