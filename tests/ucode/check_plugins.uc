'use strict';

/*
 * ucode check_plugins.uc <mode> <output.json> <golden.json> <plugins-status.json>
 * Compares a generator output produced with the fixture plugins of <mode>
 * against the golden made without plugins, and checks the status file.
 */

import { readfile } from 'fs';

const mode = ARGV[0];
const out = json(readfile(ARGV[1]));
const golden = json(readfile(ARGV[2]));
const status = json(readfile(ARGV[3]));
let failed = 0;

function check(ok, label, got) {
	if (!ok)
		failed++;
	print(ok ? 'PASS' : 'FAIL', ': plugins/', mode, ': ', label, ok ? '' : sprintf(' (got %J)', got), '\n');
}

function result(name) {
	return status.plugins?.[name]?.status;
}

if (mode === 'client') {
	const rule = shift(out.route.rules);
	check(rule?.domain_suffix?.[0] === 'plugin.example', 'a rule can be put in front of the built-in ones', rule);
	check(rule?.domain_suffix?.[1] === 'bypass_mainland_china.tun.false.ctx.example', 'ctx carries routing_mode, proxy_mode and ipv6_support', rule);
	check(out.log.level === 'debug' && !('timestamp' in out.log), 'a returned copy replaces the config, nulls are dropped', out.log);
	out.log.level = golden.log.level;
	out.log.timestamp = golden.log.timestamp;
	check(sprintf('%J', out) === sprintf('%J', golden), 'nothing else changed (failed plugins rolled back, disabled one ignored)', null);

	check(result('10-front-rule') === 'applied', '10-front-rule applied', status.plugins);
	check(result('20-syntax-error') === 'error' && match(status.plugins['20-syntax-error'].error, /Syntax error/), 'a syntax error is reported', status.plugins['20-syntax-error']);
	check(result('30-throws') === 'error' && match(status.plugins['30-throws'].error, /plugin gave up/), 'an exception is reported', status.plugins['30-throws']);
	check(!('40-switched-off' in status.plugins), 'a disabled plugin is not run', status.plugins);
	check(result('50-server-only') === 'unused', 'a plugin without client() is marked unused', status.plugins);
	check(result('60-returns-copy') === 'applied', '60-returns-copy applied', status.plugins);
	check(!status.fallback && type(status.time) === 'int' && type(status.plugins['10-front-rule'].mtime) === 'int', 'status has time and mtime, no fallback', status);
} else if (mode === 'fallback') {
	check(sprintf('%J', out) === sprintf('%J', golden), 'a config failing sing-box check is replaced by the one without plugins', null);
	check(status.fallback === true && match(status.check_error, /^FATAL.*unknown outbound type: no-such-type/), 'the fallback and the check error (without colours) are recorded', status);
	check(result('20-bad-outbound') === 'applied', 'the plugins themselves ran', status.plugins);
} else if (mode === 'server') {
	check(out.log.level === 'debug', 'server() changes the server config', out.log);
	out.log.level = golden.log.level;
	check(sprintf('%J', out) === sprintf('%J', golden), 'nothing else changed', null);
	check(result('10-debug-log') === 'applied', 'the status file of the server records the plugin', status.plugins);
}

exit(failed ? 1 : 0);
