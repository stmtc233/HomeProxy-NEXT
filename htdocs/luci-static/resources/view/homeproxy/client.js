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

		let subinfo = [];
		for (let suburl of (uci.get(data[0], 'subscription', 'subscription_url') || [])) {
			try {
				const url = new URL(suburl);
				const urlhash = hp.calcStringMD5(suburl.replace(/#.*$/, ''));
				const title = url.hash ? decodeURIComponent(url.hash.slice(1)) : url.hostname;
				subinfo.push({ hash: urlhash, title: title });
			} catch(e) {}
		}

		let sub_nodes = {};
		for (let info of subinfo)
			sub_nodes[info.hash] = [];

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
			urltest_choices['sub_' + info.hash] = String.format(_('[Subscription] %s (All nodes)'), info.title);
			for (let node of sub_nodes[info.hash]) {
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

		s = m.section(form.TypedSection);
		s.render = function () {
			const updateStatus = () => hp.getServiceStatus('sing-box-c').then((res) => {
				let view = document.getElementById('service_status');
				view.innerHTML = hp.renderStatus(_('HomeProxy NEXT'), features.version, res);
			});
			poll.add(updateStatus);

			return E('div', { class: 'cbi-section', id: 'status_bar',
				style: 'display: flex; flex-wrap: wrap; align-items: center; gap: 0.5em 1em' }, [
					E('p', { id: 'service_status', style: 'margin: 0' }, _('Collecting data...')),
					E('button', {
						class: 'btn cbi-button cbi-button-reload',
						title: _('Restart the HomeProxy service'),
						click: ui.createHandlerFn(this, () => restartService().then(updateStatus))
					}, [ _('Restart') ])
			]);
		}

		const ctx = { uciconfig: data[0], features, hosts, proxy_nodes, urltest_choices };

		s = m.section(form.NamedSection, 'config', 'homeproxy');

		for (let tab of [ routing, routing_mode, routing_node, routing_rule, dns, dns_server, dns_rule, ruleset, control, dns_cache ])
			tab.render(s, ctx);

		return m.render();
	}
});
