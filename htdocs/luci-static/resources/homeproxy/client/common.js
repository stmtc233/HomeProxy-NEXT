/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require dom';
'require form';
'require uci';
'require ui';
'require validation';

/*
 * A stored value that points at a section the select no longer offers (it
 * was deleted or disabled) stays as it is, listed under its own entry and
 * refused by validation: falling back to the first choice would change the
 * setting behind the user's back on the next save.
 */
function missingLabel(uciconfig, value) {
	let target = uci.get(uciconfig, value);
	return target ? _('%s (disabled)').format(target.label || value) : _('%s (deleted)').format(value);
}

function missingError() {
	return _('It is deleted or disabled, choose another one.');
}

/*
 * list.load(): list the missing values (a list option may hold several),
 * remember them for validate() and isValid(); a list widget does not run
 * validate() on the values it holds, so isValid() is what refuses the save.
 */
function listMissing(option, uciconfig, section_id, value) {
	/* a modal works on a copy of the option, which must not share the record */
	option.missing = Object.assign({}, option.missing);
	option.missing[section_id] = (Array.isArray(value) ? value : [ value ]).filter((v) =>
		typeof(v) === 'string' && v !== '' && !(option.keylist || []).includes(v));
	if (!option.missing[section_id].length)
		return;

	for (let v of option.missing[section_id])
		option.value(v, missingLabel(uciconfig, v));

	if (!option.checks_missing) {
		const holdsMissing = (o, sid, val) => (val != null) && (Array.isArray(val) ? val : [ val ]).some((v) => o.missing?.[sid]?.includes(v));
		const validate = option.validate,
		      isValid = option.isValid,
		      getValidationError = option.getValidationError,
		      renderWidget = option.renderWidget;

		option.validate = function(sid, val) {
			return holdsMissing(this, sid, val) ? missingError() : validate.apply(this, arguments);
		};
		option.isValid = function(sid) {
			return !holdsMissing(this, sid, this.formvalue(sid)) && isValid.apply(this, arguments);
		};
		option.getValidationError = function(sid) {
			return holdsMissing(this, sid, this.formvalue(sid)) ? missingError() : getValidationError.apply(this, arguments);
		};
		/* the items of a list are marked one by one */
		option.renderWidget = function(sid) {
			const node = renderWidget.apply(this, arguments);
			if (node && node.querySelectorAll)
				for (let item of node.querySelectorAll('.item'))
					if (holdsMissing(this, sid, item.querySelector('input')?.value)) {
						item.style.color = 'red';
						item.title = missingError();
					}
			return node;
		};
		option.checks_missing = true;
	}
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
	uniqueName: uniqueName,
	copySection: copySection,

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

			let value = this.super('load', section_id);
			listMissing(this, uciconfig, section_id, value);
			return value;
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
		const modes = () => uci.sections(uciconfig, 'routing_mode').map((res) => [ res['.name'], res.label || res['.name'] ]);
		const has_mode = (sid) => modes().some((m) => m[0] === uci.get(uciconfig, sid, 'routing_mode'));
		let current = null;

		const choices = () => {
			let res = modes();
			if (uci.sections(uciconfig, ss.sectiontype).some((rule) => !has_mode(rule['.name'])))
				res.push([ '', _('Without a mode (not used)') ]);
			return res;
		};
		/* settled before the rows load: a row only has values for the mode it was loaded with */
		const settle = () => {
			let list = choices();
			if (current == null || !list.some((c) => c[0] === current)) {
				let default_mode = uci.get(uciconfig, 'routing', 'default_mode');
				current = list.some((c) => c[0] === default_mode) ? default_mode : (list.length ? list[0][0] : '');
			}
			mode_option.default = current;
			return list;
		};

		ss.filter = (section_id) => {
			settle();
			return current ? (uci.get(uciconfig, section_id, 'routing_mode') === current) : !has_mode(section_id);
		};

		mode_option.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			for (let m of modes())
				this.value(m[0], m[1]);

			let value = this.super('load', section_id);
			listMissing(this, uciconfig, section_id, value);
			return value;
		};
		mode_option.rmempty = false;

		/* a copy keeps the label, numbered when the target mode has it already */
		ss.handleCopyTo = function(section_id, mode) {
			const src = uci.get(uciconfig, section_id);
			const taken = (label) => uci.sections(uciconfig, this.sectiontype).some((res) => res.routing_mode === mode && res.label === label);
			let label = src.label || section_id;
			for (let n = 2; taken(label); n++)
				label = (src.label || section_id) + ' ' + n;

			copySection(uciconfig, src, uniqueName(uciconfig, section_id + '_copy'), { routing_mode: mode, label: label });
			return this.map.save(null, true);
		};

		ss.renderRowActions = function(section_id) {
			const td = form.GridSection.prototype.renderRowActions.apply(this, arguments);
			const buttons = td.lastElementChild;

			buttons.insertBefore(E('button', {
				'class': 'btn cbi-button cbi-button-neutral',
				'title': _('Copy the rule to a routing mode'),
				'click': ui.createHandlerFn(this, () => {
					const others = modes().filter((m) => m[0] !== current);
					const select = E('select', { 'class': 'cbi-input-select' },
						modes().map((m) => E('option', {
							'value': m[0],
							'selected': (m[0] === (others.length ? others[0][0] : current)) ? '' : null
						}, [ m[1] ])));

					/* the copy is saved with the rows' unsaved edits, as an add would be */
					ui.showModal(_('Copy to'), [
						E('p', _('Copies %s to the routing mode chosen below.').format(uci.get(uciconfig, section_id, 'label') || section_id)),
						E('div', { 'class': 'cbi-value' }, [
							E('label', { 'class': 'cbi-value-title' }, [ _('Routing mode') ]),
							E('div', { 'class': 'cbi-value-field' }, [ select ])
						]),
						E('div', { 'class': 'right' }, [
							E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('Cancel') ]),
							' ',
							E('button', {
								'class': 'btn cbi-button-positive',
								'click': ui.createHandlerFn(this, () => this.map.parse()
									.then(() => this.handleCopyTo(section_id, select.value))
									.then(ui.hideModal))
							}, [ _('Copy') ])
						])
					]);
				})
			}, [ _('Copy to') ]), buttons.lastElementChild);

			return td;
		};

		o.renderWidget = function(section_id, option_index, cfgvalue) {
			let list = settle();
			let grid = E('div');
			let renderGrid = () => ss.load().then(() => ss.render()).then((node) => dom.content(grid, node));
			let select = E('select', {
				'class': 'cbi-input-select',
				'change': ui.createHandlerFn(this, (ev) => {
					/* keep what was edited in the rows before they go */
					return ss.parse().then(() => {
						current = ev.target.value;
						mode_option.default = current;
						return renderGrid();
					}).then(() => {
						/* options with depends render hidden, only a map render reveals them */
						this.map.checkDepends();
					}).catch(() => {
						ev.target.value = current;
					});
				})
			}, list.map((c) => E('option', { 'value': c[0], 'selected': (c[0] === current) ? '' : null }, [ c[1] ])));

			return renderGrid().then(() => E('div', {}, [
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, [ _('Routing mode') ]),
					E('div', { 'class': 'cbi-value-field' }, [ select ])
				]),
				grid
			]));
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
	 * option default; a missing one is kept and refused, see missingLabel().
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

			let value = (cfgvalue != null) ? cfgvalue : this.default;
			let missing = (value != null && value !== '' && !Object.prototype.hasOwnProperty.call(choices, value)) ? value : null;
			if (missing != null) {
				choices[missing] = missingLabel(uciconfig, missing);
				sort.push(missing);
			}

			let widget = new ui.Select(value, choices, {
				id: this.cbid(section_id),
				size: this.size,
				sort: sort,
				widget: this.widget,
				optional: this.optional,
				orientation: this.orientation,
				placeholder: this.placeholder,
				validate: (val) => (missing != null && val === missing) ? missingError() : this.validate(section_id, val),
				disabled: (this.readonly != null) ? this.readonly : this.map.readonly
			});

			return widget.render();
		};
		option.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id) || this.default || '';
			if (Object.prototype.hasOwnProperty.call(fixed, val))
				return fixed[val];
			let target = uci.get(uciconfig, val);
			if (!target || target.enabled !== '1')
				return missingLabel(uciconfig, val);
			return target.label || target['.name'];
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
