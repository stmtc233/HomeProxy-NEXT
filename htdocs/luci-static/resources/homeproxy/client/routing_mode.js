/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';
'require rpc';
'require uci';
'require ui';

'require homeproxy as hp';
'require homeproxy.client.common as common';

const RULE_TYPES = [ 'routing_rule', 'dns_rule' ];

const callTemplateApply = rpc.declare({
	object: 'luci.homeproxy',
	method: 'template_apply',
	params: ['add'],
	expect: { '': {} }
});

/* staged changes of this session would land on top of the template */
const callRevert = rpc.declare({
	object: 'uci',
	method: 'revert',
	params: ['config']
});

function applyTemplate(add) {
	return L.resolveDefault(callRevert('homeproxy'), {}).then(() => {
		return L.resolveDefault(callTemplateApply(add), {});
	}).then((res) => {
		if (res.result)
			return window.location.reload();

		ui.hideModal();
		ui.addNotification(null, E('p', _('Failed to apply the template: %s').format(res.error || _('Unknown error.'))));
	});
}

function confirmTemplate(title, text, action, add) {
	ui.showModal(title, [
		E('p', text),
		E('div', { 'class': 'right' }, [
			E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('Cancel') ]),
			' ',
			E('button', {
				'class': 'btn cbi-button-negative',
				'click': ui.createHandlerFn(null, applyTemplate, add)
			}, [ action ])
		])
	]);
}

function modeRules(uciconfig, section_id, sectiontype) {
	return uci.sections(uciconfig, sectiontype).filter((res) => res.routing_mode === section_id);
}

function uniqueName(uciconfig, base) {
	let name = base;
	for (let n = 2; uci.get(uciconfig, name); n++)
		name = base + '_' + n;
	return name;
}

function copySection(uciconfig, src, name, overrides) {
	uci.add(uciconfig, src['.type'], name);
	for (let k in src)
		if (k.charAt(0) !== '.')
			uci.set(uciconfig, name, k, Array.isArray(src[k]) ? src[k].slice() : src[k]);
	for (let k in overrides)
		uci.set(uciconfig, name, k, overrides[k]);
}

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

		/* a copy takes the rules along, under the same names with _copy */
		ss.handleCopy = function(section_id) {
			let src = uci.get(uciconfig, section_id);
			let name = uniqueName(uciconfig, section_id + '_copy');
			let label = _('%s copy').format(src.label || section_id);
			for (let n = 2; uci.sections(uciconfig, 'routing_mode').some((res) => res.label === label); n++)
				label = _('%s copy').format(src.label || section_id) + ' ' + n;

			copySection(uciconfig, src, name, { label: label });
			for (let sectiontype of RULE_TYPES)
				for (let rule of modeRules(uciconfig, section_id, sectiontype))
					copySection(uciconfig, rule, uniqueName(uciconfig, rule['.name'] + '_copy'), { routing_mode: name });

			return this.map.save(null, true);
		};

		ss.handleSetDefault = function(section_id) {
			uci.set(uciconfig, 'routing', 'default_mode', section_id);
			return this.map.save(null, true);
		};

		/* the rules of a mode go with it, and the default moves on to the first mode left */
		ss.handleRemove = function(section_id) {
			const routing_rules = modeRules(uciconfig, section_id, 'routing_rule'),
			      dns_rules = modeRules(uciconfig, section_id, 'dns_rule');
			const remove = () => {
				for (let rule of routing_rules.concat(dns_rules))
					uci.remove(uciconfig, rule['.name']);
				uci.remove(uciconfig, section_id);
				if (uci.get(uciconfig, 'routing', 'default_mode') === section_id) {
					let rest = uci.sections(uciconfig, 'routing_mode');
					uci.set(uciconfig, 'routing', 'default_mode', rest.length ? rest[0]['.name'] : 'nil');
				}
				return this.map.save(null, true);
			};

			if (!routing_rules.length && !dns_rules.length)
				return remove();

			ui.showModal(_('Delete routing mode'), [
				E('p', _('The mode %s is deleted together with its %d routing rules and %d DNS rules.')
					.format(uci.get(uciconfig, section_id, 'label') || section_id, routing_rules.length, dns_rules.length)),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('Cancel') ]),
					' ',
					E('button', {
						'class': 'btn cbi-button-negative',
						'click': ui.createHandlerFn(this, () => remove().then(ui.hideModal))
					}, [ _('Delete') ])
				])
			]);
		};

		ss.renderRowActions = function(section_id) {
			let td = form.GridSection.prototype.renderRowActions.apply(this, arguments);
			let buttons = td.lastElementChild;
			let is_default = (uci.get(uciconfig, 'routing', 'default_mode') === section_id);

			buttons.insertBefore(E('button', {
				'class': 'btn cbi-button cbi-button-neutral',
				'title': _('Copy the mode with its rules'),
				'click': ui.createHandlerFn(this, 'handleCopy', section_id)
			}, [ _('Copy') ]), buttons.lastElementChild);
			buttons.insertBefore(E('button', {
				'class': 'btn cbi-button cbi-button-apply',
				'title': _('The mode sing-box starts in'),
				'disabled': is_default ? '' : null,
				'click': ui.createHandlerFn(this, 'handleSetDefault', section_id)
			}, [ is_default ? _('Default') : _('Set as default') ]), buttons.lastElementChild);

			return td;
		};

		so = ss.option(form.Value, 'label', _('Name'),
			_('The name sing-box and the dashboard show for the mode. A renamed mode that is active in the dashboard falls back to the default mode on the next start.'));
		so.load = L.bind(hp.loadDefaultLabel, this, uciconfig);
		so.validate = L.bind(hp.validateUniqueValue, this, uciconfig, 'routing_mode', 'label');
		so.modalonly = true;

		so = ss.option(form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.option(form.DummyValue, '_rules', _('Rules'));
		so.cfgvalue = function(section_id) {
			return _('%d routing, %d DNS').format(
				modeRules(uciconfig, section_id, 'routing_rule').length,
				modeRules(uciconfig, section_id, 'dns_rule').length);
		};

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

		o = s.taboption('routing_mode', form.Button, '_template_add', _('Template modes'),
			_('Adds the modes of the default template that are missing (Rule, RuleAllowAds, Global and Direct), with the routing nodes, DNS servers and rule-sets they use. A mode whose name is already taken is left out.'));
		o.inputtitle = _('Add the template modes');
		o.inputstyle = 'add';
		o.onclick = function() {
			confirmTemplate(_('Template modes'),
				_('The missing template modes are added, and unsaved changes to HomeProxy are discarded.'),
				_('Add the template modes'), true);
		};

		o = s.taboption('routing_mode', form.Button, '_template', _('Default template'),
			_('Replaces the routing modes, routing nodes, routing rules, DNS servers, DNS rules and rule-sets with the default template. ' +
			'Its modes are Rule (mainland China direct, ads blocked, the rest through Proxy), RuleAllowAds (the same without blocking ads), Global (everything through Proxy) and Direct; ' +
			'Proxy picks Auto (the fastest of all nodes), a single node or direct.'));
		o.inputtitle = _('Reset to the template');
		o.inputstyle = 'reset';
		o.onclick = function() {
			confirmTemplate(_('Default template'),
				_('All routing modes, routing nodes, routing rules, DNS servers, DNS rules and rule-sets are replaced by the template, and unsaved changes to HomeProxy are discarded.'),
				_('Reset to the template'), false);
		};
	}
});
