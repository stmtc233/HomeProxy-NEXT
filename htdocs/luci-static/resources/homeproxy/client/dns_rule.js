/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';
'require uci';

'require homeproxy as hp';
'require homeproxy.client.common as common';

return baseclass.extend({
	render(s, ctx) {
		const { uciconfig } = ctx;
		let o, ss, so;

		s.tab('dns_rule', _('DNS Rules'));
		o = s.taboption('dns_rule', form.SectionValue, '_dns_rule', form.GridSection, 'dns_rule');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		ss.addremove = true;
		ss.rowcolors = true;
		ss.sortable = true;
		ss.nodescriptions = true;
		ss.modaltitle = L.bind(hp.loadModalTitle, this, _('DNS rule'), _('Add a DNS rule'), uciconfig);
		ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, uciconfig);
		ss.renderSectionAdd = L.bind(hp.renderSectionAdd, this, ss);

		ss.tab('field_other', _('Other fields'));
		ss.tab('field_host', _('Host/IP fields'));
		ss.tab('field_port', _('Port fields'));
		ss.tab('fields_process', _('Process fields'));

		so = ss.taboption('field_other', form.Value, 'label', _('Label'));
		so.load = L.bind(hp.loadDefaultLabel, this, uciconfig);
		so.validate = L.bind(hp.validateUniqueValue, this, uciconfig, 'dns_rule', 'label');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.taboption('field_other', form.ListValue, 'mode', _('Mode'),
			_('The default rule uses the following matching logic:<br/>' +
			'<code>(domain || domain_suffix || domain_keyword || domain_regex)</code> &&<br/>' +
			'<code>(port || port_range)</code> &&<br/>' +
			'<code>(source_ip_cidr || source_ip_is_private)</code> &&<br/>' +
			'<code>(source_port || source_port_range)</code> &&<br/>' +
			'<code>other fields</code>.<br/>' +
			'Additionally, included rule sets can be considered merged rather than as a single rule sub-item.'));
		so.value('default', _('Default'));
		so.default = 'default';
		so.rmempty = false;
		so.readonly = true;
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'ip_version', _('IP version'));
		so.value('4', _('IPv4'));
		so.value('6', _('IPv6'));
		so.value('', _('Both'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'query_type', _('Query type'),
			_('Match query type.'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'network', _('Network'));
		so.value('tcp', _('TCP'));
		so.value('udp', _('UDP'));
		so.value('', _('Both'));

		so = ss.taboption('field_other', form.MultiValue, 'protocol', _('Protocol'),
			_('Sniffed protocol, see <a target="_blank" href="https://sing-box.sagernet.org/configuration/route/sniff/">Sniff</a> for details.'));
		so.value('bittorrent', _('BitTorrent'));
		so.value('dtls', _('DTLS'));
		so.value('http', _('HTTP'));
		so.value('quic', _('QUIC'));
		so.value('rdp', _('RDP'));
		so.value('ssh', _('SSH'));
		so.value('stun', _('STUN'));
		so.value('tls', _('TLS'));

		so = ss.taboption('field_other', form.DynamicList, 'user', _('User'),
			_('Match user name.'));
		so.modalonly = true;

		so = ss.taboption('field_other', hp.CBIStaticList, 'rule_set', _('Rule set'),
			_('Match rule set. DNS: rules referencing rule-sets that contain query_type are incompatible with legacy address filters (ip_cidr / ip_is_private) — use match_response instead (1.14).'));
		so.load = common.loadSectionChoices(uciconfig, 'ruleset', {});
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'rule_set_ip_cidr_match_source', _('Rule set IP CIDR as source IP'),
			_('Make IP CIDR in rule sets match the source IP.'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'invert', _('Invert'),
			_('Invert match result.'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'action', _('Action'));
		so.value('route', _('Route'));
		so.value('route-options', _('Route options'));
		so.value('reject', _('Reject'));
		so.value('predefined', _('Predefined'));
		so.value('evaluate', _('Evaluate (1.14)'));
		so.value('respond', _('Respond (1.14)'));
		so.default = 'route';
		so.rmempty = false;
		so.editable = true;
		so.validate = function(section_id, value) {
			if (!section_id || value !== 'respond')
				return true;

			/* respond returns the response saved by an earlier evaluate rule */
			let evaluated = false, found = false;
			uci.sections(uciconfig, 'dns_rule', (res) => {
				if (found)
					return;
				if (res['.name'] === section_id)
					found = true;
				else if (res.enabled === '1' && res.action === 'evaluate')
					evaluated = true;
			});

			return evaluated || _('A Respond rule must come after an enabled Evaluate rule.');
		};

		so = ss.taboption('field_other', form.ListValue, 'server', _('Server'),
			_('Tag of the target dns server.'));
		so.default = 'default-dns';
		so.rmempty = false;
		so.editable = true;
		so.depends('action', 'route');
		so.depends('action', 'evaluate');
		common.bindSectionSelect(so, uciconfig, 'dns_server', common.builtinDnsServers());
		so.write = common.writeAndSyncSelect;

		so = ss.taboption('field_other', form.Flag, 'dns_disable_cache', _('Disable dns cache'),
			_('Disable cache and save cache in this query.'));
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'rewrite_ttl', _('Rewrite TTL'),
			_('Rewrite TTL in DNS responses.'));
		so.datatype = 'uinteger';
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'client_subnet', _('EDNS Client subnet'),
			_('Append a <code>edns0-subnet</code> OPT extra record with the specified IP prefix to every query by default.<br/>' +
			'If value is an IP address instead of prefix, <code>/32</code> or <code>/128</code> will be appended automatically.'));
		so.datatype = 'or(cidr, ipaddr)';
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'match_response', _('Match response'),
			_('1 matches the latest untagged evaluate result; other values match an evaluate tag (1.14).'));
		so.depends('action', 'route');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'evaluate_tag', _('Evaluate tag'),
			_('Optional tag for this evaluate result.'));
		so.depends('action', 'evaluate');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'race', _('Race'),
			_('Judge this response-dependent rule in parallel; first match wins (1.14).'));
		so.depends({'action': 'route', 'match_response': /[\s\S]/});
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'speculative', _('Speculative'),
			_('Send the query before pending race rules are judged (1.14).'));
		so.depends('action', 'route');
		so.depends('action', 'evaluate');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'disable_optimistic_cache', _('Disable optimistic cache'),
			_('Disable optimistic DNS caching for this query.'));
		so.depends('action', 'route');
		so.depends('action', 'evaluate');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'dns_timeout', _('Query timeout'),
			_('Override dns.timeout for this query, in seconds.'));
		so.datatype = 'uinteger';
		so.depends('action', 'route');
		so.depends('action', 'evaluate');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'remove_client_subnet', _('Remove EDNS client subnet'),
			_('Remove the edns0-subnet record from the query (1.14).'));
		so.depends('action', 'route');
		so.depends('action', 'evaluate');
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'response_rcode', _('Response RCode'),
			_('Match the evaluated response code (requires match_response).'));
		for (let rc of [ 'NOERROR', 'FORMERR', 'SERVFAIL', 'NXDOMAIN', 'NOTIMP', 'REFUSED' ])
			so.value(rc);
		so.depends({'action': 'route', 'match_response': /[\s\S]/});
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'response_answer', _('Response answer'),
			_('Text DNS records to match in the evaluated answer.'));
		so.depends({'action': 'route', 'match_response': /[\s\S]/});
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'response_ns', _('Response NS'));
		so.depends({'action': 'route', 'match_response': /[\s\S]/});
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'response_extra', _('Response extra'));
		so.depends({'action': 'route', 'match_response': /[\s\S]/});
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'reject_method', _('Method'));
		so.value('default', _('Reply with REFUSED'));
		so.value('drop', _('Drop requests'));
		so.default = 'default';
		so.depends('action', 'reject');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'reject_no_drop', _('Don\'t drop requests'),
			_('<code>%s</code> will be temporarily overwritten to <code>%s</code> after 50 triggers in 30s if not enabled.').format(
				_('Method'), _('Drop requests')));
		so.depends('reject_method', 'default');
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'predefined_rcode', _('RCode'),
			_('The response code.'));
		so.value('NOERROR');
		so.value('FORMERR');
		so.value('SERVFAIL');
		so.value('NXDOMAIN');
		so.value('NOTIMP');
		so.value('REFUSED');
		so.default = 'NOERROR';
		so.depends('action', 'predefined');
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'predefined_answer', _('Answer'),
			_('List of text DNS record to respond as answers.'));
		so.depends('action', 'predefined');
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'predefined_ns', _('NS'),
			_('List of text DNS record to respond as name servers.'));
		so.depends('action', 'predefined');
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'predefined_extra', _('Extra records'),
			_('List of text DNS record to respond as extra records.'));
		so.depends('action', 'predefined');
		so.modalonly = true;

		hp.renderRuleMatchFields(ss, {
			ip_cidr_description: _('Match IP CIDR with the evaluated response (needs match_response; old rules are auto-wrapped in 1.14).'),
			ip_is_private_description: _('Match private IP with the evaluated response (needs match_response).'),
			extra_host_fields: (section) => {
				let o;

				o = section.taboption('field_host', form.Value, 'query_client_subnet', _('Query EDNS client subnet'),
					_('Match the EDNS Client Subnet in the query (1.14).'));
				o.datatype = 'or(cidr, ipaddr)';
				o.modalonly = true;

				o = section.taboption('field_host', form.Flag, 'query_dnssec', _('Match DNSSEC OK'),
					_('Match queries with the DNSSEC OK bit set (1.14).'));
				o.modalonly = true;
			}
		});
	}
});
