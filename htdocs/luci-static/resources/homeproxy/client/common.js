/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require dom';
'require uci';
'require ui';
'require validation';

return baseclass.extend({
	stubValidator: {
		factory: validation,
		apply(type, value, args) {
			if (value != null)
				this.value = value;

			return validation.types[type].apply(this, args);
		},
		assert(condition) {
			return !!condition;
		}
	},

	builtinDnsServers() {
		return {
			'default-dns': _('Default DNS (issued by WAN)'),
			'system-dns': _('System DNS')
		};
	},

	/*
	 * ListValue load(): the fixed choices, then every enabled section of
	 * sectiontype, re-read on each load so the list follows the other tabs.
	 */
	loadSectionChoices(uciconfig, sectiontype, fixed) {
		return function(section_id) {
			delete this.keylist;
			delete this.vallist;

			for (let i in fixed)
				this.value(i, fixed[i]);
			uci.sections(uciconfig, sectiontype, (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		};
	},

	/*
	 * Show the rules in the grid of o one routing mode at a time, picked in a
	 * select above it. mode_option (the mode of a rule, in its modal) starts
	 * at the mode shown, so a rule added there joins it. Rules whose mode is
	 * gone get an entry of their own.
	 */
	bindModeGrid(o, uciconfig, mode_option) {
		const ss = o.subsection;
		const modes = () => uci.sections(uciconfig, 'routing_mode').map((res) => res['.name']);
		const has_mode = (sid) => modes().includes(uci.get(uciconfig, sid, 'routing_mode'));
		let current = null;

		ss.filter = (section_id) => current ? (uci.get(uciconfig, section_id, 'routing_mode') === current) : !has_mode(section_id);

		mode_option.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			uci.sections(uciconfig, 'routing_mode', (res) => {
				this.value(res['.name'], res.label || res['.name']);
			});

			return this.super('load', section_id);
		};
		mode_option.rmempty = false;

		o.renderWidget = function(section_id, option_index, cfgvalue) {
			let choices = uci.sections(uciconfig, 'routing_mode').map((res) => [ res['.name'], res.label || res['.name'] ]);
			if (uci.sections(uciconfig, ss.sectiontype).some((res) => !has_mode(res['.name'])))
				choices.push([ '', _('Without a mode (not used)') ]);
			if (current == null || !choices.some((c) => c[0] === current)) {
				let default_mode = uci.get(uciconfig, 'routing', 'default_mode');
				current = choices.some((c) => c[0] === default_mode) ? default_mode : (choices.length ? choices[0][0] : '');
			}
			mode_option.default = current;

			let grid = E('div');
			let select = E('select', {
				'class': 'cbi-input-select',
				'change': ui.createHandlerFn(this, (ev) => {
					/* keep what was edited in the rows before they go */
					return ss.parse().then(() => {
						current = ev.target.value;
						mode_option.default = current;
						return ss.render();
					}).then((node) => dom.content(grid, node)).catch(() => {
						ev.target.value = current;
					});
				})
			}, choices.map((c) => E('option', { 'value': c[0], 'selected': (c[0] === current) ? '' : null }, [ c[1] ])));

			return ss.render().then((node) => {
				dom.content(grid, node);
				return E('div', {}, [
					E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title' }, [ _('Routing mode') ]),
						E('div', { 'class': 'cbi-value-field' }, [ select ])
					]),
					grid
				]);
			});
		};
	},

	/* validate(): rule labels only need to be unique within their mode */
	validateUniqueLabelInMode(uciconfig, sectiontype) {
		return function(section_id, value) {
			if (!section_id)
				return true;
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));

			let mode = this.section.formvalue(section_id, 'routing_mode');
			let duplicate = uci.sections(uciconfig, sectiontype).some((res) =>
				res['.name'] !== section_id && res.label === value && res.routing_mode === mode);

			return duplicate ? _('Expecting: %s').format(_('unique value')) : true;
		};
	},

	/*
	 * A ListValue whose choices (the fixed ones, then the enabled sections of
	 * sectiontype) are collected when the widget renders, so a grid row shows
	 * sections added in the same session. An empty value displays as the
	 * option default.
	 */
	bindSectionSelect(option, uciconfig, sectiontype, fixed, exclude_self) {
		option.renderWidget = function(section_id, option_index, cfgvalue) {
			let choices = Object.assign({}, fixed);
			let sort = Object.keys(fixed);

			uci.sections(uciconfig, sectiontype, (res) => {
				if ((!exclude_self || res['.name'] !== section_id) && res.enabled === '1') {
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
		option.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id) || this.default || '';
			if (Object.prototype.hasOwnProperty.call(fixed, val))
				return fixed[val];
			let target = uci.get(uciconfig, val);
			return target ? (target.label || target['.name']) : val;
		};
	},

	/* write(): also update the select shown in the grid row after a modal save */
	writeAndSyncSelect(section_id, formvalue) {
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
	}
});
