/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 */

'use strict';
'require dom';
'require fs';
'require rpc';
'require ui';
'require view';

/*
 * The plugin files in /etc/homeproxy/custom are the only state: this page
 * reads and writes them through rpcd, so a file edited over SSH shows up here
 * as is. The generators run the enabled ones and record the outcome in
 * /var/run/homeproxy/plugins-<client|server>.json.
 */

const callList = rpc.declare({
	object: 'luci.homeproxy',
	method: 'plugin_list',
	expect: { '': {} }
});

const callRead = rpc.declare({
	object: 'luci.homeproxy',
	method: 'plugin_read',
	params: ['name'],
	expect: { '': {} }
});

const callWrite = rpc.declare({
	object: 'luci.homeproxy',
	method: 'plugin_write',
	params: ['name', 'content'],
	expect: { '': {} }
});

const callRemove = rpc.declare({
	object: 'luci.homeproxy',
	method: 'plugin_remove',
	params: ['name'],
	expect: { '': {} }
});

const callSetEnabled = rpc.declare({
	object: 'luci.homeproxy',
	method: 'plugin_set_enabled',
	params: ['name', 'enabled'],
	expect: { '': {} }
});

const NAME_RE = /^[A-Za-z0-9_-]{1,64}$/;
const KINDS = [ 'client', 'server' ];

const TEMPLATE = `'use strict';

/*
 * client(config, ctx) gets the generated sing-box client config and
 * server(config, ctx) the server one, right before \`sing-box check\`.
 * Change config in place or return a new object; a null value is dropped.
 * ctx of client(): routing_mode, proxy_mode, ipv6_support, uci (cursor).
 * ctx of server(): uci.
 * Should the result fail the check, the service starts without plugins.
 */
return {
	client: function(config, ctx) {
		// unshift(config.route.rules, { domain_suffix: [ 'example.com' ], action: 'route', outbound: 'direct-out' });
	}
};
`;

const editorStyle = 'width:100%; min-height:24em; font-family:monospace; white-space:pre; tab-size:4';

return view.extend({
	load() {
		return L.resolveDefault(callList(), {});
	},

	/*
	 * What the last run of the generators did with plugin p, and whether that
	 * is still what the files say (pending: an apply would change something).
	 */
	pluginState(p, status) {
		const ran = KINDS.filter((k) => status?.[k]);
		const results = ran.map((k) => [ k, status[k].plugins?.[p.name] ]).filter((r) => r[1]);

		if (!p.enabled)
			return results.some((r) => r[1].status === 'applied')
				? { pending: true, text: _('Disabled, still active until applied') }
				: { pending: false, text: _('Disabled') };
		if (!results.length)
			return { pending: true, text: _('Not applied yet') };
		if (results.some((r) => r[1].mtime !== p.mtime))
			return { pending: true, text: _('Changed, not applied yet') };

		const texts = [];
		let error = false;
		for (let [ kind, r ] of results) {
			const side = (kind === 'client') ? _('client') : _('server');
			if (r.status === 'applied' && status[kind].fallback) {
				texts.push(_('Rolled back on the %s: the config failed sing-box check').format(side));
				error = true;
			} else if (r.status === 'applied') {
				texts.push(_('Active on the %s').format(side));
			} else if (r.status === 'error') {
				texts.push(_('Error on the %s: %s').format(side, r.error));
				error = true;
			}
		}
		if (!texts.length)
			texts.push(_('No client() or server() function'));

		return { pending: false, error: error, text: texts.join('; ') };
	},

	/* a plugin that took part in the last run but whose file is gone */
	removedSinceRun(plugins, status) {
		const present = {};
		for (let p of plugins)
			present[p.name] = true;

		return KINDS.some((k) => Object.keys(status?.[k]?.plugins || {}).some((name) =>
			!present[name] && status[k].plugins[name].status === 'applied'));
	},

	refresh() {
		return this.load().then((data) => dom.content(this.container, this.renderContent(data)));
	},

	handleApply() {
		return fs.exec('/etc/init.d/homeproxy', ['reload']).then((res) => {
			if (res.code !== 0)
				ui.addNotification(null, E('p', _('Reload failed (exit code %d), see the HomeProxy log on the Service Status page.').format(res.code)));
		}).catch((err) => {
			if (/time(d)? ?out/i.test(String(err)))
				ui.addNotification(null, E('p', _('The reload is taking a while and goes on in the background.')), 'info');
			else
				ui.addNotification(null, E('p', _('Reload failed: %s').format(err)));
		}).then(() => this.refresh());
	},

	handleToggle(p) {
		return callSetEnabled(p.name, !p.enabled).then((res) => {
			if (!res.result)
				ui.addNotification(null, E('p', _('Failed to change plugin %s: %s').format(p.name, res.error)));
			return this.refresh();
		});
	},

	handleRemove(p) {
		if (!confirm(_('Delete the plugin %s?').format(p.name)))
			return;

		return callRemove(p.name).then((res) => {
			if (!res.result)
				ui.addNotification(null, E('p', _('Failed to delete plugin %s: %s').format(p.name, res.error)));
			return this.refresh();
		});
	},

	/* p: the plugin to edit, or null for a new one */
	showEditor(p, content) {
		const nameInput = E('input', {
			class: 'cbi-input-text',
			placeholder: '10-my-plugin',
			style: 'width:100%'
		});
		const editor = E('textarea', { class: 'cbi-input-textarea', style: editorStyle, spellcheck: 'false' }, [ content ]);
		const message = E('p', { style: 'color:red; white-space:pre-wrap; font-family:monospace' });

		const save = () => {
			const name = p ? p.name : nameInput.value.trim();
			if (!NAME_RE.test(name)) {
				message.textContent = _('Expecting: %s').format(_('a name of letters, digits, - and _ (up to 64)'));
				return;
			}

			return callWrite(name, editor.value).then((res) => {
				if (!res.result) {
					message.textContent = res.error;
					return;
				}
				ui.hideModal();
				return this.refresh();
			});
		};

		ui.showModal(p ? _('Edit plugin %s').format(p.name) : _('Add a plugin'), [
			p ? '' : E('div', { class: 'cbi-value' }, [
				E('label', { class: 'cbi-value-title' }, _('Name')),
				E('div', { class: 'cbi-value-field' }, [ nameInput ]),
				E('div', { class: 'cbi-value-description' },
					_('Plugins run in the order of their names, e.g. 10-first, 20-second.'))
			]),
			editor,
			message,
			E('div', { class: 'right' }, [
				E('button', { class: 'btn', click: ui.hideModal }, [ _('Cancel') ]),
				' ',
				E('button', { class: 'btn cbi-button-positive', click: ui.createHandlerFn(this, save) }, [ _('Save') ])
			])
		], 'cbi-modal');
	},

	handleEdit(p) {
		return callRead(p.name).then((res) => {
			if (res.content == null)
				ui.addNotification(null, E('p', _('Failed to read plugin %s: %s').format(p.name, res.error)));
			else
				this.showEditor(p, res.content);
		});
	},

	renderContent(data) {
		const plugins = data.plugins || [];
		const status = data.status || {};
		const states = plugins.map((p) => this.pluginState(p, status));
		const pending = states.some((s) => s.pending) || this.removedSinceRun(plugins, status);
		const nodes = [];

		for (let kind of KINDS)
			if (status[kind]?.fallback)
				nodes.push(E('div', { class: 'alert-message error' }, [
					E('p', (kind === 'client')
						? _('The client config failed sing-box check with the plugins applied, so it runs without them:')
						: _('The server config failed sing-box check with the plugins applied, so it runs without them:')),
					E('pre', { style: 'white-space:pre-wrap' }, [ status[kind].check_error || '' ])
				]));

		if (pending)
			nodes.push(E('div', { class: 'alert-message warning' }, [
				E('p', _('The plugins changed since the last run. Apply to regenerate the configuration.')),
				E('button', { class: 'btn cbi-button-apply', click: ui.createHandlerFn(this, 'handleApply') }, [ _('Apply') ])
			]));

		const rows = plugins.map((p, i) => E('tr', { class: 'tr' }, [
			E('td', { class: 'td', style: 'font-family:monospace' }, [ p.file ]),
			E('td', { class: 'td', style: states[i].error ? 'color:red' : (states[i].pending ? 'color:#d08000' : '') }, [ states[i].text ]),
			E('td', { class: 'td right' }, [
				E('button', {
					class: 'btn cbi-button ' + (p.enabled ? 'cbi-button-negative' : 'cbi-button-positive'),
					click: ui.createHandlerFn(this, 'handleToggle', p)
				}, [ p.enabled ? _('Disable') : _('Enable') ]),
				' ',
				E('button', { class: 'btn cbi-button-edit', click: ui.createHandlerFn(this, 'handleEdit', p) }, [ _('Edit') ]),
				' ',
				E('button', { class: 'btn cbi-button-remove', click: ui.createHandlerFn(this, 'handleRemove', p) }, [ _('Delete') ])
			])
		]));

		nodes.push(E('table', { class: 'table' }, [
			E('tr', { class: 'tr table-titles' }, [
				E('th', { class: 'th' }, _('File')),
				E('th', { class: 'th' }, _('Status')),
				E('th', { class: 'th right' }, _('Actions'))
			]),
			...(rows.length ? rows : [ E('tr', { class: 'tr placeholder' }, [
				E('td', { class: 'td', colspan: 3 }, _('No plugins yet.'))
			]) ])
		]));

		nodes.push(E('div', { class: 'cbi-section-create' }, [
			E('button', { class: 'btn cbi-button-add', click: ui.createHandlerFn(this, () => this.showEditor(null, TEMPLATE)) }, [ _('Add a plugin') ]),
			' ',
			E('button', { class: 'btn cbi-button-apply', click: ui.createHandlerFn(this, 'handleApply') }, [ _('Apply') ])
		]));

		return nodes;
	},

	render(data) {
		this.container = E('div', { class: 'cbi-section' }, this.renderContent(data));

		return E([], [
			E('h2', _('Custom Plugins')),
			E('div', { class: 'cbi-map-descr' },
				_('Small ucode scripts that change the generated sing-box configuration, kept in <code>/etc/homeproxy/custom/</code>, which upgrades leave alone. ' +
				'<code>name.uc</code> is enabled, <code>name.uc.disabled</code> disabled; files edited over SSH show up here as well. ' +
				'Changes take effect after Apply (or <code>/etc/init.d/homeproxy reload</code>).<br/>' +
				'A plugin runs as root with full access to the router; only add code you understand.')),
			this.container
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
