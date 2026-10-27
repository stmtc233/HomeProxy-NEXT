/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';

'require homeproxy as hp';
'require homeproxy.client.common as common';

return baseclass.extend({
	render(s, ctx) {
		const { uciconfig, features, proxy_nodes, urltest_choices } = ctx;
		let o, ss, so;

		s.tab('routing', _('Routing Settings'));

		o = s.taboption('routing', form.ListValue, 'main_node', _('Main node'));
		o.value('nil', _('Disable'));
		o.value('urltest', _('URLTest'));
		for (let i in proxy_nodes)
			o.value(i, proxy_nodes[i]);
		o.default = 'nil';
		o.depends({'routing_mode': 'custom', '!reverse': true});
		o.rmempty = false;

		o = s.taboption('routing', hp.CBIStaticList, 'main_urltest_nodes', _('URLTest nodes'),
			_('List of nodes to test.'));
		for (let i in urltest_choices)
			o.value(i, urltest_choices[i]);
		o.depends('main_node', 'urltest');
		o.rmempty = false;

		o = s.taboption('routing', form.Value, 'main_urltest_interval', _('Test interval'),
			_('The test interval in seconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '180';
		o.depends('main_node', 'urltest');

		o = s.taboption('routing', form.Value, 'main_urltest_tolerance', _('Test tolerance'),
			_('The test tolerance in milliseconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '50';
		o.depends('main_node', 'urltest');

		o = s.taboption('routing', form.ListValue, 'main_udp_node', _('Main UDP node'));
		o.value('nil', _('Disable'));
		o.value('same', _('Same as main node'));
		o.value('urltest', _('URLTest'));
		for (let i in proxy_nodes)
			o.value(i, proxy_nodes[i]);
		o.default = 'nil';
		o.depends({'routing_mode': /^((?!custom).)+$/, 'proxy_mode': /^((?!redirect$).)+$/});
		o.rmempty = false;

		o = s.taboption('routing', hp.CBIStaticList, 'main_udp_urltest_nodes', _('URLTest nodes'),
			_('List of nodes to test.'));
		for (let i in urltest_choices)
			o.value(i, urltest_choices[i]);
		o.depends('main_udp_node', 'urltest');
		o.rmempty = false;

		o = s.taboption('routing', form.Value, 'main_udp_urltest_interval', _('Test interval'),
			_('The test interval in seconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '180';
		o.depends('main_udp_node', 'urltest');

		o = s.taboption('routing', form.Value, 'main_udp_urltest_tolerance', _('Test tolerance'),
			_('The test tolerance in milliseconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '50';
		o.depends('main_udp_node', 'urltest');

		o = s.taboption('routing', form.Value, 'dns_server', _('DNS server'),
			_('Support UDP, TCP, DoH, DoQ, DoT. TCP protocol will be used if not specified.'));
		o.value('wan', _('WAN DNS (read from interface)'));
		o.value('1.1.1.1', _('CloudFlare Public DNS (1.1.1.1)'));
		o.value('208.67.222.222', _('Cisco Public DNS (208.67.222.222)'));
		o.value('8.8.8.8', _('Google Public DNS (8.8.8.8)'));
		o.value('', '---');
		o.value('223.5.5.5', _('Aliyun Public DNS (223.5.5.5)'));
		o.value('119.29.29.29', _('Tencent Public DNS (119.29.29.29)'));
		o.value('117.50.10.10', _('ThreatBook Public DNS (117.50.10.10)'));
		o.default = '8.8.8.8';
		o.rmempty = false;
		o.depends({'routing_mode': 'custom', '!reverse': true});
		o.validate = function(section_id, value) {
			if (section_id && !['wan'].includes(value)) {
				if (!value)
					return _('Expecting: %s').format(_('non-empty value'));

				let ipv6_support = this.section.formvalue(section_id, 'ipv6_support');
				try {
					let url = new URL(value.replace(/^.*:\/\//, 'http://'));
					if (common.stubValidator.apply('hostname', url.hostname))
						return true;
					else if (common.stubValidator.apply('ip4addr', url.hostname))
						return true;
					else if ((ipv6_support === '1') && common.stubValidator.apply('ip6addr', url.hostname.match(/^\[(.+)\]$/)?.[1]))
						return true;
					else
						return _('Expecting: %s').format(_('valid DNS server address'));
				} catch(e) {}

				if (!common.stubValidator.apply((ipv6_support === '1') ? 'ipaddr' : 'ip4addr', value))
					return _('Expecting: %s').format(_('valid DNS server address'));
			}

			return true;
		}

		o = s.taboption('routing', form.Value, 'china_dns_server', _('China DNS server'),
			_('The dns server for resolving China domains. Support UDP, TCP, DoH, DoQ, DoT.'));
		o.value('wan', _('WAN DNS (read from interface)'));
		o.value('223.5.5.5', _('Aliyun Public DNS (223.5.5.5)'));
		o.value('210.2.4.8', _('CNNIC Public DNS (210.2.4.8)'));
		o.value('119.29.29.29', _('Tencent Public DNS (119.29.29.29)'));
		o.value('117.50.10.10', _('ThreatBook Public DNS (117.50.10.10)'));
		o.depends('routing_mode', 'bypass_mainland_china');
		o.default = '223.5.5.5';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (section_id && !['wan'].includes(value)) {
				if (!value)
					return _('Expecting: %s').format(_('non-empty value'));

				try {
					let url = new URL(value.replace(/^.*:\/\//, 'http://'));
					if (common.stubValidator.apply('hostname', url.hostname))
						return true;
					else if (common.stubValidator.apply('ip4addr', url.hostname))
						return true;
					else if (common.stubValidator.apply('ip6addr', url.hostname.match(/^\[(.+)\]$/)?.[1]))
						return true;
					else
						return _('Expecting: %s').format(_('valid DNS server address'));
				} catch(e) {}

				if (!common.stubValidator.apply('ipaddr', value))
					return _('Expecting: %s').format(_('valid DNS server address'));
			}

			return true;
		}

		o = s.taboption('routing', form.ListValue, 'routing_mode', _('Routing mode'));
		o.value('gfwlist', _('GFWList'));
		o.value('bypass_mainland_china', _('Bypass mainland China'));
		o.value('proxy_mainland_china', _('Only proxy mainland China'));
		o.value('custom', _('Custom routing'));
		o.value('global', _('Global'));
		o.default = 'bypass_mainland_china';
		o.rmempty = false;
		o.onchange = function(ev, section_id, value) {
			if (section_id && value === 'custom')
				this.map.save(null, true);
		}

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

		o = s.taboption('routing', form.Flag, 'cn_ip_fallback', _('CN-IP DNS fallback (sing-box 1.14)'),
			_('When the main DNS returns a mainland China IP, re-resolve via China DNS using evaluate/match_response.'));
		o.depends('routing_mode', 'bypass_mainland_china');
		o.rmempty = false;

		o = s.taboption('routing', form.Flag, 'kill_switch', _('Kill switch'),
			_('Drop forwarded traffic to overseas destinations while the sing-box client is not running (crash, restart, reload or failed start), so nothing leaks out directly. Mainland China and private addresses stay reachable.<br/>' +
			'Stopping the service from the init script lifts the block; if the client cannot start, internet access stays blocked until it is fixed or the service is stopped.'));
		o.depends({'routing_mode': /^(bypass_mainland_china|custom|global)$/});
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('routing', form.Flag, 'block_https_rr', _('Block HTTPS/SVCB DNS records'),
			_('Answer HTTPS (type 65) and SVCB (type 64) queries with an empty response. Keeps clients off HTTPS-RR/ECH, which this DNS chain cannot serve through some proxies; disable it if ECH is wanted.'));
		o.default = o.enabled;
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
		o.depends('routing_mode', 'custom');

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
			_('Bypass mainland China traffic via firewall rules by default.'));
		so.rmempty = false;

		so = ss.option(form.Flag, 'find_neighbor', _('Find neighbor hosts'),
			_('Enable neighbor resolution so rules can match LAN devices by hostname (1.14).'));
		so.rmempty = false;

		so = ss.option(form.ListValue, 'domain_strategy', _('Domain strategy'),
			_('If set, the requested domain name will be resolved to IP before routing.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);

		so = ss.option(form.ListValue, 'default_outbound', _('Default outbound'),
			_('Default outbound for connections not matched by any routing rules.'));
		so.load = common.loadSectionChoices(uciconfig, 'routing_node', {
			'nil': _('Disable (the service)'),
			'direct-out': _('Direct'),
			'block-out': _('Block')
		});
		so.default = 'nil';
		so.rmempty = false;

		so = ss.option(form.ListValue, 'default_outbound_dns', _('Default outbound DNS'),
			_('Default DNS server for resolving domain name in the server address.'));
		so.load = common.loadSectionChoices(uciconfig, 'dns_server', common.builtinDnsServers());
		so.default = 'default-dns';
		so.rmempty = false;
	}
});
