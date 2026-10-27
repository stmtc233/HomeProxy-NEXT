#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# The plugin methods of the rpcd object luci.homeproxy, run from the real
# file with its directories moved into $WORK: names are validated, the files
# are the state (<name>.uc on, <name>.uc.disabled off), a syntax error is
# refused before anything is saved.

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-rpcd-plugins-test}"

ROOT="$(cd "$ROOT" && pwd)"

rm -rf "$WORK"
mkdir -p "$WORK/hp" "$WORK/run"

sed -e "s#^const HP_DIR = '/etc/homeproxy';#const HP_DIR = '$WORK/hp';#" \
    -e "s#^const RUN_DIR = '/var/run/homeproxy';#const RUN_DIR = '$WORK/run';#" \
    -e "s#'/etc/homeproxy/scripts/homeproxy.uc'#'$ROOT/root/etc/homeproxy/scripts/homeproxy.uc'#" \
    -e "s#^return { 'luci.homeproxy': methods };##" \
    "$ROOT/root/usr/share/rpcd/ucode/luci.homeproxy" > "$WORK/rpcd.uc"

cat >> "$WORK/rpcd.uc" <<TEST
const dir = '$WORK/hp/custom', run = '$WORK/run';
let failed = 0;
function call(method, args) { return methods[method].call({ args: args ?? {} }); }
function check(ok, label, got) {
	if (!ok)
		failed++;
	print(ok ? 'PASS' : 'FAIL', ': rpcd plugins: ', label, ok ? '' : sprintf(' (got %J)', got), '\n');
}
function names() { return map(call('plugin_list').plugins, (p) => p.file); }

let r = call('plugin_list');
check(length(r.plugins) === 0 && r.status.client === null, 'an absent directory lists nothing', r);

r = call('plugin_write', { name: 'demo', content: "return { client: function(c) {} };\r\n" });
check(r.result === true && access(dir + '/demo.uc'), 'a new plugin is saved enabled', r);
check(readfile(dir + '/demo.uc') === "return { client: function(c) {} };\n", 'line endings are normalized', readfile(dir + '/demo.uc'));
check(call('plugin_read', { name: 'demo' }).content === "return { client: function(c) {} };\n", 'a plugin can be read back', null);

for (let bad in [ '../x', 'a/b', '', 'a.b', null ]) {
	r = call('plugin_write', { name: bad, content: 'return {};' });
	check(r.result === false && r.error === 'illegal name', sprintf('the name %J is refused', bad), r);
}

r = call('plugin_write', { name: 'broken', content: 'return { client: function( };' });
check(r.result === false && match(r.error, /Syntax error/) && index(r.error, 'broken.uc') >= 0, 'a syntax error is refused with a message', r);
check(join(' ', names()) === 'demo.uc' && !length(filter(require('fs').lsdir(dir), (f) => substr(f, 0, 1) === '.')), 'a refused plugin leaves no file behind', require('fs').lsdir(dir));

r = call('plugin_write', { name: 'big', content: sprintf('%1000000s', '') });
check(r.result === false, 'an oversized plugin is refused', r);

check(call('plugin_set_enabled', { name: 'demo', enabled: false }).result === true && join(' ', names()) === 'demo.uc.disabled', 'disabling renames to .uc.disabled', names());
check(call('plugin_list').plugins[0].enabled === false, 'the list shows it disabled', call('plugin_list'));
check(call('plugin_write', { name: 'demo', content: 'return {};' }).result === true && join(' ', names()) === 'demo.uc.disabled', 'saving a disabled plugin keeps it disabled', names());
check(call('plugin_set_enabled', { name: 'demo', enabled: true }).result === true && join(' ', names()) === 'demo.uc', 'enabling renames back', names());
check(call('plugin_set_enabled', { name: 'demo', enabled: true }).result === true, 'enabling an enabled plugin is a no-op', names());

writefile(dir + '/demo.uc.disabled', 'return {};\n');
r = call('plugin_set_enabled', { name: 'demo', enabled: false });
check(r.result === false && join(' ', names()) === 'demo.uc demo.uc.disabled', 'an enabled and a disabled copy are not overwritten', r);
unlink(dir + '/demo.uc.disabled');

writefile(dir + '/notes.txt', 'x');
writefile(dir + '/bad name.uc', 'x');
check(join(' ', names()) === 'demo.uc', 'files that are no plugins are not listed', names());

writefile(run + '/plugins-client.json', '{"time":1,"plugins":{"demo":{"status":"applied","mtime":2}}}');
writefile(run + '/plugins-server.json', 'not json');
r = call('plugin_list');
check(r.status.client?.plugins?.demo?.status === 'applied' && r.status.server === null, 'the last run of each generator is reported', r.status);

check(call('plugin_remove', { name: 'demo' }).result === true && !length(names()), 'a plugin can be removed', names());
r = call('plugin_remove', { name: 'demo' });
check(r.result === false && r.error === 'no such plugin', 'removing a missing plugin is an error', r);
check(call('plugin_read', { name: 'demo' }).error === 'no such plugin', 'reading a missing plugin is an error', null);

exit(failed ? 1 : 0);
TEST

ucode "$WORK/rpcd.uc"
