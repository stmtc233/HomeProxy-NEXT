/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require dom';
'require form';
'require fs';
'require homeproxy as hp';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

const css = '				\
	padding: 10px;			\
	text-align: left;		\
}					\
	padding: .5rem;			\
	word-break: break-all;		\
	margin: 0;			\
}					\
.description {				\
	background-color: #33ccff;	\
}';

const hp_dir = '/var/run/homeproxy';

function getConnStat(o, site) {
	const callConnStat = rpc.declare({
		object: 'luci.homeproxy',
		method: 'connection_check',
		params: ['site'],
		expect: { '': {} }
	});

	o.default = E('div', { 'style': 'cbi-value-field' }, [
		E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, () => {
				return L.resolveDefault(callConnStat(site), {}).then((ret) => {
                                        let ele = o.default.firstElementChild.nextElementSibling;
					if (ret.result) {
						ele.style.setProperty('color', 'green');
                                                ele.innerHTML = _('passed');
					} else {
						ele.style.setProperty('color', 'red');
                                                ele.innerHTML = _('failed');
					}
				});
			})
		}, [ _('Check') ]),
		' ',
		E('strong', { 'style': 'color:gray' }, _('unchecked')),
	]);
}

const callResUpdate = rpc.declare({
	object: 'luci.homeproxy',
	method: 'resources_update',
	params: ['type'],
	expect: { '': {} }
});

const resourceTypes = [ 'china_ip4', 'china_ip6', 'china_list', 'gfw_list', 'geoip_cn', 'geosite_cn' ];

function getResVersion(o, type) {
	const callResVersion = rpc.declare({
		object: 'luci.homeproxy',
		method: 'resources_get_version',
		params: ['type'],
		expect: { '': {} }
	});

	return L.resolveDefault(callResVersion(type), {}).then((res) => {
		let spanTemp = E('div', { 'style': 'cbi-value-field' }, [
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, () => {
					return L.resolveDefault(callResUpdate(type), {}).then((res) => {
						switch (res.status) {
						case 0:
							o.description = _('Successfully updated.');
							break;
						case 1:
							o.description = _('Update failed.');
							break;
						case 2:
							o.description = _('Already in updating.');
							break;
						case 3:
							o.description = _('Already at the latest version.');
							break;
						default:
							o.description = _('Unknown error.');
							break;
						}

						return o.map.reset();
					});
				})
			}, [ _('Check update') ]),
			' ',
			E('strong', { 'style': (res.error ? 'color:red' : 'color:green') },
				[ res.error ? 'not found' : res.version ]
			),
		]);

		o.default = spanTemp;
	});
}

function renderBackup() {
	const callConfigExport = rpc.declare({
		object: 'luci.homeproxy',
		method: 'config_export',
		params: ['include_nodes'],
		expect: { '': {} }
	});

	const callConfigImport = rpc.declare({
		object: 'luci.homeproxy',
		method: 'config_import',
		params: ['include_nodes'],
		expect: { '': {} }
	});

	const import_tmpfile = '/tmp/homeproxy_import.tmp';

	const export_nodes = E('input', { 'type': 'checkbox', 'id': 'hp_export_nodes', 'checked': '' });
	const import_nodes = E('input', { 'type': 'checkbox', 'id': 'hp_import_nodes', 'checked': '' });
	const file_input = E('input', { 'type': 'file', 'accept': '.json,application/json', 'style': 'display:none' });

	const pad = (n) => (n < 10 ? '0' : '') + n;

	function doExport() {
		return L.resolveDefault(callConfigExport(export_nodes.checked), {}).then((res) => {
			if (!res.result || !res.backup) {
				ui.addNotification(null, E('p', _('Failed to export the configuration: %s').format(res.error || _('Unknown error.'))));
				return;
			}

			const now = new Date();
			const name = 'homeproxy-backup-%s%s%s-%s%s%s%s.json'.format(
				now.getFullYear(), pad(now.getMonth() + 1), pad(now.getDate()),
				pad(now.getHours()), pad(now.getMinutes()), pad(now.getSeconds()),
				res.backup.include_nodes ? '' : '-no-nodes');

			const url = URL.createObjectURL(new Blob([ JSON.stringify(res.backup, null, 2) ], { type: 'application/json' }));
			const a = E('a', { 'href': url, 'download': name, 'style': 'display:none' });
			document.body.appendChild(a);
			a.click();
			document.body.removeChild(a);
			setTimeout(() => URL.revokeObjectURL(url), 1000);
		});
	}

	function doImport(text, with_nodes) {
		return fs.write(import_tmpfile, text).then(() => {
			return L.resolveDefault(callConfigImport(with_nodes), {});
		}).then((res) => {
			ui.hideModal();

			if (!res.result) {
				ui.addNotification(null, E('p', _('Failed to import the configuration: %s').format(res.error || _('Unknown error.'))));
				return;
			}

			ui.showModal(_('Import configuration'), [
				E('p', _('Successfully imported %d sections.').format(res.sections)),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-positive',
						'click': () => window.location.reload()
					}, [ _('Reload page') ])
				])
			]);
		}).catch((err) => {
			ui.hideModal();
			ui.addNotification(null, E('p', _('Failed to import the configuration: %s').format(err)));
		});
	}

	function onFileSelected() {
		const file = file_input.files[0];
		file_input.value = '';
		if (!file)
			return;

		const reader = new FileReader();
		reader.onload = () => {
			let backup;
			try {
				backup = JSON.parse(reader.result);
			} catch (e) {
				backup = null;
			}

			if (!backup || backup.format !== 'homeproxy-backup' || !Array.isArray(backup.sections)) {
				ui.addNotification(null, E('p', _('Not a valid HomeProxy backup file.')));
				return;
			}

			const with_nodes = import_nodes.checked && backup.include_nodes === true;
			const nodes_in_file = (backup.include_nodes === true);
			const text = reader.result;

			let notes = [
				E('p', _('The current configuration will be replaced by the content of %s.').format(file.name))
			];
			if (with_nodes)
				notes.push(E('p', _('Nodes and subscriptions will be replaced as well.')));
			else if (nodes_in_file)
				notes.push(E('p', _('The nodes and subscriptions in the file will be ignored, the current ones are kept.')));
			else
				notes.push(E('p', _('The file contains no nodes or subscriptions, the current ones are kept.')));

			ui.showModal(_('Import configuration'), [
				...notes,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, [ _('Cancel') ]),
					' ',
					E('button', {
						'class': 'btn cbi-button cbi-button-negative',
						'click': ui.createHandlerFn(this, () => doImport(text, with_nodes))
					}, [ _('Import') ])
				])
			]);
		};
		reader.onerror = () => ui.addNotification(null, E('p', _('Failed to read the file.')));
		reader.readAsText(file);
	}

	file_input.addEventListener('change', onFileSelected);

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', _('Backup and restore')),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Export configuration')),
			E('div', { 'class': 'cbi-value-field' }, [
				E('label', {}, [ export_nodes, ' ', _('Include nodes and subscriptions') ]),
				E('br'),
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'style': 'margin-top: 4px;',
					'click': ui.createHandlerFn(this, doExport)
				}, [ _('Export') ]),
				E('div', { 'class': 'cbi-value-description' },
					_('Download the HomeProxy configuration as a JSON file. Leave the option off to share the settings without your nodes and subscription URLs.'))
			])
		]),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Import configuration')),
			E('div', { 'class': 'cbi-value-field' }, [
				E('label', {}, [ import_nodes, ' ', _('Import nodes and subscriptions') ]),
				E('br'),
				file_input,
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'style': 'margin-top: 4px;',
					'click': () => file_input.click()
				}, [ _('Import') ]),
				E('div', { 'class': 'cbi-value-description' },
					_('Restore the configuration from a file exported here. Without the option above the current nodes and subscriptions are kept.'))
			])
		])
	]);
}

/*
 * One resource after another, as one update script call can take a while.
 * Like the scheduled update, apply the new lists (dnsmasq + fw4) only while
 * the client runs: refresh_lists would otherwise set up its firewall rules.
 */
function updateAllResources(o) {
	const counts = { 0: 0, 3: 0, failed: 0 };
	let chain = Promise.resolve();

	for (let type of resourceTypes)
		chain = chain.then(() => L.resolveDefault(callResUpdate(type), {})).then((res) => {
			counts[(res.status === 0 || res.status === 3) ? res.status : 'failed']++;
		});

	return chain.then(() => counts[0] ? hp.getServiceStatus('sing-box-c') : false).then((running) => {
		if (running)
			return fs.exec('/etc/init.d/homeproxy', ['refresh_lists']);
	}).then(() => {
		o.description = _('%d updated, %d already up to date, %d failed.').format(counts[0], counts[3], counts.failed) +
			(counts.failed ? ' ' + _('See the HomeProxy log below.') : '');
		return o.map.reset();
	});
}

function getRuntimeLog(o, name, _option_index, section_id, _in_table) {
	const filename = o.option.split('_')[1];

	let section, log_level_el;
	switch (filename) {
	case 'homeproxy':
		section = null;
		break;
	case 'sing-box-c':
		section = 'config';
		break;
	case 'sing-box-s':
		section = 'server';
		break;
	}

	if (section) {
		const selected = uci.get('homeproxy', section, 'log_level') || 'warn';
		const choices = {
			trace: _('Trace'),
			debug: _('Debug'),
			info: _('Info'),
			warn: _('Warn'),
			error: _('Error'),
			fatal: _('Fatal'),
			panic: _('Panic')
		};

		log_level_el = E('select', {
			'id': o.cbid(section_id),
			'class': 'cbi-input-select',
			'style': 'margin-left: 4px; width: 6em;',
			'change': ui.createHandlerFn(this, (ev) => {
				uci.set('homeproxy', section, 'log_level', ev.target.value);
				return o.map.save(null, true).then(() => {
					hp.applyChanges(true);
				});
			})
		});

		Object.keys(choices).forEach((v) => {
			log_level_el.appendChild(E('option', {
				'value': v,
				'selected': (v === selected) ? '' : null
			}, [ choices[v] ]));
		});
	}

	const callLogClean = rpc.declare({
		object: 'luci.homeproxy',
		method: 'log_clean',
		params: ['type'],
		expect: { '': {} }
	});

	const log_textarea = E('div', { 'id': 'log_textarea' },
		E('img', {
			'src': L.resource('icons/loading.svg'),
			'alt': _('Loading'),
			'style': 'vertical-align:middle'
		}, _('Collecting data...'))
	);

	let log;
	poll.add(L.bind(() => {
		return fs.read_direct(String.format('%s/%s.log', hp_dir, filename), 'text')
		.then((res) => {
			log = E('pre', { 'wrap': 'pre' }, [
				res.trim() || _('Log is empty.')
			]);

			dom.content(log_textarea, log);
		}).catch((err) => {
			if (err.toString().includes('NotFoundError'))
				log = E('pre', { 'wrap': 'pre' }, [
					_('Log file does not exist.')
				]);
			else
				log = E('pre', { 'wrap': 'pre' }, [
					_('Unknown error: %s').format(err)
				]);

			dom.content(log_textarea, log);
		});
	}));

	return E([
		E('style', [ css ]),
		E('div', {'class': 'cbi-map'}, [
			E('h3', {'name': 'content', 'style': 'align-items: center; display: flex;'}, [
				_('%s log').format(name),
				log_level_el || '',
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'style': 'margin-left: 4px;',
					'click': ui.createHandlerFn(this, () => {
						return L.resolveDefault(callLogClean(filename), {});
					})
				}, [ _('Clean log') ])
			]),
			E('div', {'class': 'cbi-section'}, [
				log_textarea,
				E('div', {'style': 'text-align:right'},
					E('small', {}, _('Refresh every %s seconds.').format(L.env.pollinterval))
				)
			])
		])
	]);
}

return view.extend({
	render() {
		let m, s, o;

		m = new form.Map('homeproxy');

		s = m.section(form.NamedSection, 'config', 'homeproxy', _('Connection check'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_check_baidu', _('BaiDu'));
		o.cfgvalue = L.bind(getConnStat, this, o, 'baidu');

		o = s.option(form.DummyValue, '_check_google', _('Google'));
		o.cfgvalue = L.bind(getConnStat, this, o, 'google');

		s = m.section(form.NamedSection, 'config', 'homeproxy', _('Resources management'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_update_all', _('All resources'));
		o.cfgvalue = function() {
			return E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, updateAllResources, this)
			}, [ _('Update all') ]);
		};
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_china_ip4_version', _('China IPv4 list version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'china_ip4');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_china_ip6_version', _('China IPv6 list version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'china_ip6');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_china_list_version', _('China list version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'china_list');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_gfw_list_version', _('GFW list version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'gfw_list');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_geoip_cn_version', _('GeoIP CN rule-set version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'geoip_cn');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_geosite_cn_version', _('GeoSite CN rule-set version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'geosite_cn');
		o.rawhtml = true;

		o = s.option(form.Value, 'github_token', _('GitHub token'));
		o.password = true;
		o.renderWidget = function() {
			let node = form.Value.prototype.renderWidget.apply(this, arguments);

			(node.querySelector('.control-group') || node).appendChild(E('button', {
				'class': 'cbi-button cbi-button-apply',
				'title': _('Save'),
				'click': ui.createHandlerFn(this, () => {
					return this.map.save(null, true).then(() => {
						hp.applyChanges(true);
					});
				}, this.option)
			}, [ _('Save') ]));

			return node;
		}

		s = m.section(form.NamedSection, 'config', 'homeproxy');
		s.anonymous = true;

		o = s.option(form.DummyValue, '_backup');
		o.render = L.bind(renderBackup, this);

		s = m.section(form.NamedSection, 'config', 'homeproxy');
		s.anonymous = true;

		o = s.option(form.DummyValue, '_homeproxy_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('HomeProxy NEXT'));

		o = s.option(form.DummyValue, '_sing-box-c_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('sing-box client'));

		o = s.option(form.DummyValue, '_sing-box-s_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('sing-box server'));

		return m.render();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
