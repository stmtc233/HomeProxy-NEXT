# luci-app-homeproxy tests

Automated checks for the pieces that `sing-box check` cannot validate: the
share-link parsers, the UCI→JSON generators and the LuCI form definitions.

## Running

```sh
tests/run.sh
```

* The **LuCI form snapshots** run locally and only need `node`. They re-render
  the node/client/server views through a mock LuCI runtime and diff the result
  against `tests/snapshots/*.json`.
* The **ucode tests** need `ucode`; the generator cases additionally run
  `sing-box check`, so they need sing-box ≥ 1.14 as well (available on an
  OpenWrt/ImmortalWrt target). When the host running `tests/run.sh` has neither,
  the checkout is copied over ssh to `$HP_TEST_HOST` (default
  `root@192.168.1.1`) and the tests run there:

  ```sh
  HP_TEST_HOST=root@192.168.1.1 tests/run.sh
  HP_TEST_DIR=/tmp/hp-tests      tests/run.sh
  ```

`tests/run.sh` exits non-zero if anything fails. The ucode part can also be run
on its own on a target:

```sh
sh tests/ucode/run.sh "$PWD"
```

### In CI / with Docker

`.github/workflows/test.yml` runs the form snapshots and the whole ucode suite
on every push to `main` and every pull request. The ucode job starts the
ImmortalWrt rootfs image (pinned by digest) with `--privileged` (the fw4 and
kill switch tests need network namespaces), mounts the checkout and the
official static sing-box build into it, and runs `tests/ci/ucode-in-rootfs.sh`.
That script installs the few missing packages, lays out
`/etc/homeproxy/{scripts,resources}` and `/etc/config/homeproxy` the way the
package installs them, and calls `tests/ucode/run.sh`.

The same thing works on any machine with Docker (`/tmp/sing-box` being the
`sing-box` binary from `sing-box-<version>-linux-amd64-musl.tar.gz`; the image
and version are the ones pinned in `test.yml`):

```sh
docker run --rm --privileged \
	-v "$PWD:/src:ro" -v "/tmp/sing-box:/usr/bin/sing-box:ro" \
	-v "/tmp/hp-ucode-tests:/tmp/hp-ucode-tests" \
	immortalwrt/rootfs:x86-64-openwrt-25.12.2 \
	sh /src/tests/ci/ucode-in-rootfs.sh /src
```

## What is covered

| Path | Checks |
| --- | --- |
| `tests/i18n-coverage.py` | Reports how many `po/templates/homeproxy.pot` strings have a non-fuzzy, non-empty `po/zh_Hans/homeproxy.po` translation. Technical tokens that stay as-is are listed in `tests/i18n-ignore.txt`; anything else missing produces a warning annotation (`--warn-below 100` by default) and a job-summary entry. Run by `.github/workflows/i18n.yml` on push/PR and before a release. |
| `tests/luci-form-snapshot.js` | Dumps every option (name, kind, title, description, depends, values, datatype/default/…) of the node, client and server views, including the sub-forms of `SectionValue` options and the client tab modules. Diffs against `tests/snapshots/{node,client,server}.json`, so a refactor that changes a field or its visibility fails. |
| `tests/frontend-md5.js` | `hp.calcStringMD5()` against Node's `crypto` MD5 over the UTF-8 bytes (ASCII, CJK, emoji, flags, ZWJ sequences, block-boundary lengths). The frontend hashes subscription URLs into `sub_<hash>` urltest entries, and `update_subscriptions.uc` drops entries whose hash matches no URL, so the two sides have to agree. |
| `tests/frontend-status.js` | `hp.getServiceStatus()` / `hp.renderStatus()` through a fake rpc: a running, stopped or unregistered instance gives RUNNING / NOT RUNNING, an rpcd error gives STATUS UNKNOWN instead of NOT RUNNING. |
| `tests/frontend-client-common.js` | The section-backed selects shared by the client tabs (`homeproxy/client/common.js`): fixed choices first, then only the enabled sections (optionally without the row's own section), unset values shown as the option default, stored values shown by label, and the grid select updated after a modal save. |
| `tests/frontend-defaults.js` | Every form default in the snapshots that belongs to an option listed in `DEFAULTS` (`homeproxy.uc`) has the same value, so a page never shows one value while the backend falls back to another. |
| `tests/frontend-plugins.js` | The status column of the plugin page (`view/homeproxy/plugins.js`): a plugin file is compared with the last generator run, so a new, edited, disabled or deleted plugin shows up as not applied yet, and an error or a rollback by `sing-box check` is reported per side. |
| `tests/ucode/test_homeproxy_utils.uc` | `executeCommand()` return shape, stderr/exit-code capture, binary detection, a 700 KiB read (the one-shot 512 KiB read used to truncate large subscription lists), `isValidCIDR()` prefix/address validation incl. template-injection input, and a descriptor-leak check (200 calls). |
| `tests/ucode/test_homeproxy_utils_inject.uc` | The failure path of `executeCommand()`: the script stages a copy of `homeproxy.uc` whose `system()` call is replaced by `die()`, then checks that the exception still propagates and that neither descriptor leaks. |
| `tests/ucode/test_wget_flavor.uc` | The `wget --version` probe (`classifyWgetFlavor()`) and the command line `wGETVerbose()` builds from it. `run.sh` points the module at a stub wget and runs the file twice — once answering like GNU wget (expects `-nv`), once like uclient-fetch (expects `-q` and no GNU-only option at all). |
| `tests/ucode/test_wget_verbose_uclient.uc` | Runs `wGETVerbose()` against the target's real `/bin/uclient-fetch` (skipped where it is absent). The request goes to a closed loopback port, so the point is only that uclient-fetch gets past getopt — a GNU-only flag in the command line fails the test. |
| `tests/ucode/test_defaults.sh` | Every `HP_DEFAULT_<OPTION>` in `scripts/defaults.sh` (the fallbacks of `init.d` and `killswitch.sh`) matches the single entry of that option in `DEFAULTS` of `homeproxy.uc` (the fallbacks of the ucode readers). |
| `tests/ucode/test_preset_rulesets.sh` | `migrate_config.uc` adds the preset CN rule-sets of the shipped config to an upgraded config exactly once: identical to the shipped sections, not again after the user deleted one, never over a section of the same name. `test_generators.sh` also runs the shipped config in the custom mode with both enabled through `sing-box check`. |
| `tests/ucode/test_rpcd_plugins.sh` | The plugin methods of the rpcd object `luci.homeproxy`, run from the real file with its directories moved into a scratch directory: name validation (no path traversal), a syntax error refused before saving, enable/disable as a rename that keeps the content, no overwrite when both copies exist, removal, and the status of the last generator runs. |
| `tests/ucode/test_killswitch.sh` | Renders the kill switch nft script (`scripts/killswitch.sh render`) for each routing mode and checks the mainland sets, the private-range exemptions, that invalid lines of a resource list never reach the script, and which modes are unsupported. With `nft` present it also validates the script (`nft -c`) and, inside a private network namespace, that `install` starts armed and keeps the armed/disarmed state across a rebuild. |
| `tests/ucode/test_update_resources.sh` | Runs `scripts/update_resources.sh` against a stub `wget` that answers the GitHub API, fails on chosen hosts and logs every URL: the mirrors are tried in order (fastly → gcore → cdn.jsdelivr → raw.githubusercontent.com, the last with its own `<repo>/<sha>/<file>` URL shape), nothing else is fetched once one succeeds, and nothing is installed when all fail. |
| `tests/ucode/test_fw4_names.sh` | Keeps the fw4 chain/set inventory in `scripts/fw4_names.sh` (used by `init.d/homeproxy` to clean up on stop) in sync with the objects declared in `scripts/firewall_post.ut`. |
| `tests/ucode/test_fw4_cleanup.sh` | The fw4 helpers in `scripts/fw4_names.sh` that `init.d/homeproxy` uses to skip a fw4 reload whose snippets did not change and to take the homeproxy objects out in one nft batch: only inventory objects are listed, a partly loaded snippet is not taken for loaded, a chain fw4 still jumps to survives the fallback, and reload-on-blank-snippets plus one batch removes everything. Runs in a network namespace against a stand-in fw4 table (skipped without `nft`/`unshare`). |
| `tests/ucode/test_parse_uri.uc` | Per-scheme assertions on the `parse_uri()` result: anytls, http/https, hysteria, hysteria2/hy2, snell, socks(4/4a/5/5h), shadowsocks (SIP002 base64 + plain + plugin, Shadowrocket), trojan (ws/grpc), tuic, vless (reality/ws/http/httpupgrade), vmess (ws/h2/httpupgrade/grpc) and SIP008 objects, plus the rejection paths (unsupported kcp/quic, no QUIC support, invalid port, unknown scheme). |
| `tests/ucode/test_generators.sh` | Runs `generate_client.uc`/`generate_server.uc` against the UCI fixtures in `tests/fixtures/generators/` inside a scratch directory (the `uci` cursor and `HP_DIR`/`RUN_DIR` are redirected) and validates each result with `sing-box check`. The `client`, `rules`, `global-tun`, `bypass-direct`, `custom-extras` and `server` cases are additionally compared byte for byte against the golden snapshots `tests/snapshots/<case>.generated.json` (with the scratch directory normalized out, and the WAN DNS lookup over ubus stubbed so the result does not depend on the host), which is what catches rule-order/DNS-routing/field-emission regressions that `sing-box check` accepts. `rules.uci` sets every match field and every action-specific option of a routing rule and a DNS rule, so its golden locks how each UCI option reaches sing-box. `global-tun.uci`, `bypass-direct.uci` and `custom-extras.uci` cover the generator branches the others leave out (global mode, tun/UDP options, WireGuard endpoints, a dedicated UDP node, direct-node overrides, the domain lists — read from `<fixture>.direct_list.txt` / `.proxy_list.txt` when present —, the global DNS and custom routing options, routing-node bind/detour/resolver and the dashboard). `custom-labels.uci` covers the label-based tags of nodes, DNS servers and rule-sets: non-ASCII labels, duplicates and clashes with built-in tags (suffixed ` #2`), the `cfg-<name>-…` fallback for unlabelled sections and verbatim extra rule-set tags.  The `plugins-*` cases copy `tests/fixtures/plugins/<mode>/` into the scratch `custom/` directory and let `tests/ucode/check_plugins.uc` compare the output with the golden made without plugins: a rule put in front, `ctx`, a returned copy, a syntax error, an exception rolled back, a disabled and a server-only plugin (`client`), the fallback to the config without plugins when `sing-box check` fails (`fallback`), and `server()` (`server`), plus the `plugins-<kind>.json` status files. |

The ucode tests use the production `homeproxy.uc` (with paths rewritten where
needed), never a hand-kept copy; `validation()` calls the real
`/sbin/validate_data`, which both the target and the CI rootfs provide.

## Adding cases

* New share link → add an `expect_fields(...)` case to `test_parse_uri.uc`.
* New protocol option that reaches the generator → extend the fixtures in
  `tests/fixtures/generators/`, keeping values schema-valid so `sing-box check`
  still passes.
* Intentional LuCI form change → regenerate the snapshots:

  ```sh
  node tests/luci-form-snapshot.js . node   > tests/snapshots/node.json
  node tests/luci-form-snapshot.js . client > tests/snapshots/client.json
  node tests/luci-form-snapshot.js . server > tests/snapshots/server.json
  ```
* Intentional generated-config change → review the diff the failing run
  printed, then copy the normalized output over the golden (it is written to
  `/tmp/hp-ucode-tests/generators/<case>/normalized.json` on the host or in the
  mounted directory of the Docker run above):

  ```sh
  cp /tmp/hp-ucode-tests/generators/client/normalized.json tests/snapshots/client.generated.json
  cp /tmp/hp-ucode-tests/generators/server/normalized.json tests/snapshots/server.generated.json
  ```
