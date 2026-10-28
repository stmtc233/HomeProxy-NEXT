/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';
'require rpc';
'require ui';

'require homeproxy as hp';
'require homeproxy.client.common as common';

const callTemplateApply = rpc.declare({
	object: 'luci.homeproxy',
	method: 'template_apply',
	expect: { '': {} }
});

/* staged changes of this session would land on top of the template */
const callRevert = rpc.declare({
	object: 'uci',
	method: 'revert',
	params: ['config']
});

function applyTemplate() {
	return L.resolveDefault(callRevert('homeproxy'), {}).then(() => {
		return L.resolveDefault(callTemplateApply(), {});
	}).then((res) => {
		if (res.result)
			return window.location.reload();

		ui.hideModal();
		ui.addNotification(null, E('p', _('Failed to apply the template: %s').format(res.error || _('Unknown error.'))));
	});
}

return baseclass.extend({
	render(s, ctx) {
		const { uciconfig, features } = ctx;
		let o, ss, so;

		s.tab('routing', _('Routing Settings'));

		o = s.taboption('routing', form.Value, 'routing_port', _('Routing ports'),
			_('Specify target ports to be proxied. Multiple ports must be separated by commas.'));
		o.value('', _('All ports'));
		o.value('common', _('Common ports only (bypass P2P traffic)'));
		o.validate = function(section_id, value) {
			if (section_id && value && value !== 'common') {

				let ports = [];
				for (let i of value.split(',')) {
					if (!common.stubValidator.apply('port', i) && !common.stubValidator.apply('portrange', i))
						return _('Expecting: %s').format(_('valid port value'));
					if (ports.includes(i))
						return _('Port %s alrealy exists!').format(i);
					ports = ports.concat(i);
				}
			}

			return true;
		}

		o = s.taboption('routing', form.ListValue, 'proxy_mode', _('Proxy mode'));
		o.value('redirect', _('Redirect TCP'));
		if (features.hp_has_tproxy)
			o.value('redirect_tproxy', _('Redirect TCP + TProxy UDP'));
		if (features.hp_has_ip_full && features.hp_has_tun) {
			o.value('redirect_tun', _('Redirect TCP + Tun UDP'));
			o.value('tun', _('Tun TCP/UDP'));
		} else {
			o.description = _('To enable Tun support, you need to install <code>ip-full</code> and <code>kmod-tun</code>');
		}
		o.default = 'redirect_tproxy';
		o.rmempty = false;

		o = s.taboption('routing', form.Flag, 'ipv6_support', _('IPv6 support'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('routing', form.Flag, 'kill_switch', _('Kill switch'),
			_('Drop forwarded traffic to overseas destinations while the sing-box client is not running (crash, restart, reload or failed start), so nothing leaks out directly. Mainland China and private addresses stay reachable.<br/>' +
			'Stopping the service from the init script lifts the block; if the client cannot start, internet access stays blocked until it is fixed or the service is stopped.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('routing', form.ListValue, 'tun_dns_mode', _('TUN DNS mode (1.14)'),
			_('Since sing-box 1.14 the default (Unset) behaves as hijack: sing-box sets the platform interface DNS and hijacks port 53. On OpenWrt this overlaps with the own dnsmasq/nftables DNS hijack of this plugin, so keep Disabled on a gateway unless you need sing-box to own TUN DNS.'));
		o.value('default', _('Unset (default)'));
		o.value('disabled', _('Disabled'));
		o.value('native', _('Native'));
		o.value('hijack', _('Hijack'));
		o.depends('proxy_mode', 'redirect_tun');
		o.depends('proxy_mode', 'tun');
		o.default = 'default';
		o.rmempty = true;

		o = s.taboption('routing', form.DynamicList, 'tun_dns_address', _('TUN DNS addresses (1.14)'));
		o.datatype = 'ipaddr';
		o.depends({'proxy_mode': /^((?!custom).)+$/, 'tun_dns_mode': /^(disabled|native|hijack)$/});
		o.modalonly = true;

		o = s.taboption('routing', form.ListValue, 'udp_mapping', _('UDP NAT mapping (1.14)'));
		o.value('endpoint_independent', _('Endpoint independent'));
		o.value('address_dependent', _('Address dependent'));
		o.value('address_and_port_dependent', _('Address and port dependent'));
		o.description = _('sing-box default; recommended for home use (small NAT table, QUIC/game friendly). Choose stricter only for specific UDP issues.');
		o.depends('proxy_mode', 'redirect_tproxy');
		o.depends('proxy_mode', 'redirect_tun');
		o.depends('proxy_mode', 'tun');
		o.default = 'endpoint_independent';
		o.rmempty = false;

		o = s.taboption('routing', form.ListValue, 'udp_filtering', _('UDP NAT filtering (1.14)'));
		o.value('endpoint_independent', _('Endpoint independent'));
		o.value('address_dependent', _('Address dependent'));
		o.value('address_and_port_dependent', _('Address and port dependent'));
		o.description = _('sing-box default; recommended for home use (accepts replies from any remote after mapping). Choose stricter only for specific UDP issues.');
		o.depends('proxy_mode', 'redirect_tproxy');
		o.depends('proxy_mode', 'redirect_tun');
		o.depends('proxy_mode', 'tun');
		o.default = 'endpoint_independent';
		o.rmempty = false;

		o = s.taboption('routing', form.Value, 'udp_nat_max', _('UDP NAT sessions max (1.14)'));
		o.datatype = 'uinteger';
		o.depends('proxy_mode', 'redirect_tproxy');
		o.depends('proxy_mode', 'redirect_tun');
		o.depends('proxy_mode', 'tun');

		o = s.taboption('routing', form.Flag, 'dashboard', _('Enable dashboard (sing-box API)'),
			_('Run the sing-box 1.14 API service and serve its web dashboard at /dashboard/ on the listen address.'));
		o.rmempty = false;

		o = s.taboption('routing', form.Value, 'dashboard_listen', _('Dashboard listen address'),
			_('Address and port of the API service. Use 127.0.0.1:9090 to keep it local only.'));
		o.default = '0.0.0.0:9090';
		o.placeholder = '0.0.0.0:9090';
		o.validate = function(section_id, value) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));
			if (!/^(\[[0-9a-fA-F:.]+\]|[0-9A-Za-z.-]*):([0-9]{1,5})$/.test(value) || +value.split(':').pop() > 65535)
				return _('Expecting: %s').format(_('host:port'));
			return true;
		};
		o.depends('dashboard', '1');
		o.rmempty = false;

		o = s.taboption('routing', form.Value, 'dashboard_secret', _('Dashboard secret'),
			_('Bearer token required by the API. Strongly recommended when listening on a non-local address.'));
		o.password = true;
		o.depends('dashboard', '1');
		o.rmempty = true;

		o = s.taboption('routing', form.Value, 'dashboard_url', _('Dashboard download URL'),
			_('ZIP archive of the dashboard files. Leave empty to use the default sing-box dashboard. Downloaded into /var/run/homeproxy/dashboard/web and refreshed daily.'));
		o.placeholder = 'https://example.com/dashboard.zip';
		o.depends('dashboard', '1');
		o.rmempty = true;

		o = s.taboption('routing', form.SectionValue, '_routing', form.NamedSection, 'routing', 'homeproxy');

		ss = o.subsection;
		so = ss.option(form.ListValue, 'tcpip_stack', _('TCP/IP stack'),
			_('TCP/IP stack.'));
		if (features.with_gvisor) {
			so.value('mixed', _('Mixed'));
			so.value('gvisor', _('gVisor'));
		}
		so.value('system', _('System'));
		so.default = 'system';
		so.depends('homeproxy.config.proxy_mode', 'redirect_tun');
		so.depends('homeproxy.config.proxy_mode', 'tun');
		so.rmempty = false;
		so.onchange = function(ev, section_id, value) {
			let desc = ev.target.nextElementSibling;
			if (value === 'mixed')
				desc.innerHTML = _('Mixed <code>system</code> TCP stack and <code>gVisor</code> UDP stack.')
			else if (value === 'gvisor')
				desc.innerHTML = _('Based on google/gvisor.');
			else if (value === 'system')
				desc.innerHTML = _('Less compatibility and sometimes better performance.');
		}

		so = ss.option(form.Flag, 'endpoint_independent_nat', _('Enable endpoint-independent NAT'),
			_('Performance may degrade slightly, so it is not recommended to enable on when it is not needed.'));
		so.default = so.enabled;
		so.depends('tcpip_stack', 'mixed');
		so.depends('tcpip_stack', 'gvisor');
		so.rmempty = false;

		so = ss.option(form.Value, 'udp_timeout', _('UDP NAT expiration time'),
			_('In seconds.'));
		so.datatype = 'uinteger';
		so.placeholder = '300';
		so.depends('homeproxy.config.proxy_mode', 'redirect_tproxy');
		so.depends('homeproxy.config.proxy_mode', 'redirect_tun');
		so.depends('homeproxy.config.proxy_mode', 'tun');

		so = ss.option(form.Flag, 'bypass_cn_traffic', _('Bypass CN traffic'),
			_('Send mainland China addresses past sing-box in the firewall. The Global mode is not available while this is on: rules limited to Global are left out and it disappears from the dashboard.'));
		so.rmempty = false;

		so = ss.option(form.Flag, 'find_neighbor', _('Find neighbor hosts'),
			_('Enable neighbor resolution so rules can match LAN devices by hostname (1.14).'));
		so.rmempty = false;

		so = ss.option(form.ListValue, 'domain_strategy', _('Domain strategy'),
			_('If set, the requested domain name will be resolved to IP before routing.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);

		so = ss.option(form.Button, '_template', _('Default template'),
			_('Replaces the routing nodes, routing rules, DNS servers, DNS rules and rule-sets with the default template. ' +
			'Its default outbound Proxy picks Auto (the fastest of all nodes), a single node or direct; ' +
			'its modes, switched in the dashboard, are Rule (mainland China direct, ads blocked, the rest through Proxy), RuleAllowAds (the same without blocking ads), Global and Direct.'));
		so.inputtitle = _('Reset to the template');
		so.inputstyle = 'reset';
		so.onclick = function() {
			ui.showModal(_('Default template'), [
				E('p', _('All routing nodes, routing rules, DNS servers, DNS rules and rule-sets are replaced by the template, and unsaved changes to HomeProxy are discarded.')),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('Cancel') ]),
					' ',
					E('button', {
						'class': 'btn cbi-button-negative',
						'click': ui.createHandlerFn(this, applyTemplate)
					}, [ _('Reset to the template') ])
				])
			]);
		};

		so = ss.option(form.ListValue, 'default_outbound', _('Default outbound'),
			_('Default outbound for connections not matched by any routing rules.'));
		so.load = common.loadSectionChoices(uciconfig, 'routing_node', {
			'nil': _('Disable (the service)'),
			'direct-out': _('Direct'),
			'block-out': _('Block')
		});
		so.default = 'nil';
		so.rmempty = false;

		so = ss.option(form.Value, 'default_mode', _('Default mode'),
			_('The mode sing-box starts in, Rule if empty. Once a mode has been switched in the dashboard, that one is kept across restarts instead.'));
		so.load = common.loadClashModes(uciconfig);
		so.placeholder = 'Rule';

		so = ss.option(form.ListValue, 'default_outbound_dns', _('Default outbound DNS'),
			_('Default DNS server for resolving domain name in the server address.'));
		so.load = common.loadSectionChoices(uciconfig, 'dns_server', common.builtinDnsServers());
		so.default = 'default-dns';
		so.rmempty = false;
	}
});
