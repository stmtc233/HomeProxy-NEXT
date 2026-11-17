/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require form';
'require fs';
'require network';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

'require homeproxy as hp';
'require homeproxy.client.common as common';
'require homeproxy.client.control as control';
'require homeproxy.client.dns as dns';
'require homeproxy.client.dns_cache as dns_cache';
'require homeproxy.client.dns_rule as dns_rule';
'require homeproxy.client.dns_server as dns_server';
'require homeproxy.client.routing as routing';
'require homeproxy.client.routing_mode as routing_mode';
'require homeproxy.client.routing_node as routing_node';
'require homeproxy.client.routing_rule as routing_rule';
'require homeproxy.client.ruleset as ruleset';

/*
 * The init script waits for the WAN and regenerates everything, which can
 * outlast the RPC timeout of the browser; the restart itself goes on in rpcd
 * then, so a timeout is not reported as a failure.
 */
function restartService() {
	return fs.exec('/etc/init.d/homeproxy', ['restart']).then((res) => {
		if (res.code !== 0)
			ui.addNotification(null, E('p', _('Restart failed (exit code %d), see the HomeProxy log on the Service Status page.').format(res.code)));
	}).catch((err) => {
		if (/time(d)? ?out/i.test(String(err)))
			ui.addNotification(null, E('p', _('The restart is taking a while and goes on in the background.')), 'info');
		else
			ui.addNotification(null, E('p', _('Restart failed: %s').format(err)));
	});
}

/*
 * sing-box serves the dashboard on the port of its API. A wildcard listen
 * address is reached under the host of this page; a loopback one is out of
 * reach of the browser, so there is nothing to open.
 */
function dashboardUrl(uciconfig) {
	if (uci.get(uciconfig, 'config', 'dashboard') !== '1')
		return null;

	const listen = /^\[?([^\]]*)\]?:([0-9]+)$/.exec(uci.get(uciconfig, 'config', 'dashboard_listen') || '');
	if (!listen || /^(127\.|::1$|localhost$)/.test(listen[1]))
		return null;

	let host = listen[1];
	if (!host || host === '0.0.0.0' || host === '::')
		host = window.location.hostname;
	else if (host.includes(':'))
		host = '[' + host + ']';

	return 'http://' + host + ':' + listen[2] + '/dashboard/';
}

const callDashboardStatus = rpc.declare({
	object: 'luci.homeproxy',
	method: 'dashboard_status',
	expect: { '': {} }
});

const callDashboardUpdate = rpc.declare({
	object: 'luci.homeproxy',
	method: 'dashboard_update',
	expect: { '': {} }
});

/* `status` as dashboard_status returns it (update_resources.sh writes it) */
function renderDashboardStatus(status) {
	const updated = status?.updated ? new Date(status.updated * 1000).toLocaleString() : null;

	switch (status?.state) {
	case 'running':
		return E('em', { 'class': 'spinning' }, _('Downloading the dashboard…'));
	case 'done':
		return _('Dashboard downloaded at %s').format(updated);
	case 'failed': {
		const reasons = {
			download: _('the archive could not be downloaded, see the HomeProxy log'),
			unzip: _('the file is not a ZIP archive'),
			no_index: _('the archive has no index.html at its top level, check the dashboard download URL'),
			install: _('the files could not be installed, see the HomeProxy log'),
			interrupted: _('the download was interrupted')
		};
		return E('span', { 'style': 'color:#d9534f' }, [
			_('Dashboard download failed: %s.').format(reasons[status.error] || status.error),
			updated ? ' ' + _('The one downloaded at %s is still in use.').format(updated) : ''
		]);
	}
	default:
		return _('Dashboard not downloaded yet');
	}
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('homeproxy'),
			hp.getBuiltinFeatures(),
			network.getHostHints()
		]);
	},

	handleSaveApply(ev, mode) {
		return this.handleSave(ev).then(() => hp.applyChanges(mode == '0'));
	},

	render(data) {
		let m, s;

		let features = data[1],
		    hosts = data[2]?.hosts;

		const subinfo = hp.getSubscriptions(data[0]);

		let sub_nodes = {};
		for (let info of subinfo)
			sub_nodes[info.id] = [];

		let orphan_sub_nodes = {};
		let manual_nodes = [];

		uci.sections(data[0], 'node', (res) => {
			let nodeaddr = ((res.type === 'direct') ? res.override_address : res.address) || '',
			    nodeport = ((res.type === 'direct') ? res.override_port : res.port) || '';
			let nodename = res.label || ((common.stubValidator.apply('ip6addr', nodeaddr) ?
				String.format('[%s]', nodeaddr) : nodeaddr) + ':' + nodeport);
			let item = { id: res['.name'], label: nodename, type: res.type, grouphash: res.grouphash };

			if (res.grouphash) {
				if (sub_nodes[res.grouphash]) {
					sub_nodes[res.grouphash].push(item);
				} else {
					if (!orphan_sub_nodes[res.grouphash])
						orphan_sub_nodes[res.grouphash] = [];
					orphan_sub_nodes[res.grouphash].push(item);
				}
			} else {
				manual_nodes.push(item);
			}
		});

		let has_subscriptions = (subinfo.length > 0 || Object.keys(orphan_sub_nodes).length > 0);
		let proxy_nodes = {};
		let urltest_choices = { 'all-nodes': _('[All nodes]') };

		for (let info of subinfo) {
			urltest_choices['sub_' + info.id] = String.format(_('[Subscription] %s (All nodes)'), info.title);
			for (let node of sub_nodes[info.id]) {
				let text = String.format('[%s] [%s] %s', info.title, node.type, node.label);
				proxy_nodes[node.id] = text;
				urltest_choices[node.id] = text;
			}
		}

		for (let ghash in orphan_sub_nodes) {
			urltest_choices['sub_' + ghash] = String.format(_('[Subscription] %s (All nodes)'), _('Unknown subscription'));
			for (let node of orphan_sub_nodes[ghash]) {
				let text = String.format('[%s] [%s] %s', _('Unknown subscription'), node.type, node.label);
				proxy_nodes[node.id] = text;
				urltest_choices[node.id] = text;
			}
		}

		for (let node of manual_nodes) {
			let text = has_subscriptions ?
				String.format('[%s] [%s] %s', _('Manual'), node.type, node.label) :
				String.format('[%s] %s', node.type, node.label);
			proxy_nodes[node.id] = text;
			urltest_choices[node.id] = text;
		}

		m = new form.Map('homeproxy', _('HomeProxy NEXT'),
			_('A lean sing-box 1.14 proxy for ImmortalWrt: fewer features, each one done well.'));

		const dashboard_enabled = (uci.get(data[0], 'config', 'dashboard') === '1');
		const dashboard_url = dashboardUrl(data[0]);

		s = m.section(form.TypedSection);
		s.render = function () {
			const updateStatus = () => hp.getServiceStatus('sing-box-c').then((res) => {
				let view = document.getElementById('service_status');
				view.innerHTML = hp.renderStatus(_('HomeProxy NEXT'), features.version, res, features.core_type);

				if (dashboard_enabled)
					return L.resolveDefault(callDashboardStatus(), {}).then((status) =>
						document.getElementById('dashboard_status')?.replaceChildren(renderDashboardStatus(status)));
			});
			poll.add(updateStatus);

			const statusChildren = [
				E('p', { id: 'service_status', style: 'margin: 0' }, _('Collecting data...')),
				E('button', {
					class: 'btn cbi-button cbi-button-reload',
					title: _('Restart the HomeProxy service'),
					disabled: !features.version ? '' : null,
					click: ui.createHandlerFn(this, () => features.version ? restartService().then(updateStatus) : null)
				}, [ _('Restart') ]),
				dashboard_url ? E('button', {
					class: 'btn cbi-button cbi-button-action',
					title: _('Open the dashboard in a new tab'),
					click: () => window.open(dashboard_url, '_blank', 'noopener')
				}, [ _('Open dashboard') ]) : '',
				dashboard_enabled ? E('button', {
					class: 'btn cbi-button cbi-button-action',
					title: _('Download the dashboard again'),
					click: ui.createHandlerFn(this, () => callDashboardUpdate().then(updateStatus))
				}, [ _('Update dashboard') ]) : '',
				dashboard_enabled ? E('span', { id: 'dashboard_status' }) : ''
			];

			const statusBar = E('div', { class: 'cbi-section', id: 'status_bar',
				style: 'display: flex; flex-wrap: wrap; align-items: center; gap: 0.5em 1em' },
				statusChildren
			);

			if (!features.version) {
				return E('div', {}, [
					statusBar,
					E('div', { class: 'alert-message warning', style: 'margin-top: 1em' }, [
						E('h4', {}, _('Core not found')),
						E('p', {}, _('Neither %s nor %s is installed on the system. Please install one of them to enable the proxy service.').format('sing-box', 'sing-box-tiny'))
					])
				]);
			}

			return statusBar;
		}

		const ctx = { uciconfig: data[0], features, hosts, proxy_nodes, urltest_choices };

		s = m.section(form.NamedSection, 'config', 'homeproxy');

		for (let tab of [ routing, routing_mode, routing_node, routing_rule, dns, dns_server, dns_rule, ruleset, control, dns_cache ])
			tab.render(s, ctx);

		return m.render();
	}
});
