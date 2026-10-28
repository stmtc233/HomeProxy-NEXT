/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
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
	 * load(): suggest the clash modes sing-box lists first, then every other
	 * mode a routing or DNS rule names, re-read on each load like the above.
	 */
	loadClashModes(uciconfig) {
		return function(section_id) {
			delete this.keylist;
			delete this.vallist;

			let modes = ['Rule', 'Global', 'Direct'];
			for (let sectiontype of ['routing_rule', 'dns_rule'])
				uci.sections(uciconfig, sectiontype, (res) => {
					for (let mode of [].concat(res.clash_mode || []))
						if (!modes.includes(mode))
							modes.push(mode);
				});
			for (let mode of modes)
				this.value(mode);

			return this.super('load', section_id);
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
