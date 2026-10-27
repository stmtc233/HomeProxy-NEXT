# AGENTS.md

写给在本仓库工作的 AI 编码助手和开发者。动手前先读完本文件。

## 项目是什么

**HomeProxy NEXT**：一个以自用为主的 LuCI 透明代理模块，后端是 sing-box ≥ 1.14，运行在 ImmortalWrt / OpenWrt ≥ 24.10（firewall4 / nftables）。

### 核心原则：化繁为简

1. **不主动加功能。** 只做用户明确要求的事。不要“顺手”加协议、开关或兼容层；用户要求的新功能，也先想清楚能不能复用现有选项。
2. **把现有功能做好。** 修 bug、补测试、改善默认值和提示文案，优先级都高于新功能。
3. **行为不变是底线。** 重构必须让表单快照和生成器 golden 快照保持一致；要改行为，就单独提交，并在提交说明里写清楚。
4. **只认 sing-box 1.14。** 不写兼容 1.13 及更早版本的分支，也不保留已废弃字段。以 [sing-box 文档](https://sing-box.sagernet.org/) 为准。
5. **删比加好。** 没人用的选项、死代码、过时的迁移逻辑，确认无引用后可以删掉，并在 `CHANGELOG.md` 里记一笔。

### 不要改的标识符

对外显示的名称是 **HomeProxy NEXT**；以下内部标识保持和上游一致，不要重命名：

- 包名 `luci-app-homeproxy`、`luci-i18n-homeproxy-*`
- UCI 配置 `/etc/config/homeproxy`，以及各 section / option 名
- 路径 `/etc/homeproxy`、`/var/run/homeproxy`、`/etc/init.d/homeproxy`
- rpcd 对象 `luci.homeproxy`、ACL `luci-app-homeproxy`、LuCI 路由 `admin/services/homeproxy`
- fw4 的表、链、集合名（清单见 `root/etc/homeproxy/scripts/fw4_names.sh`）

改了这些，用户覆盖安装后旧配置会失效、防火墙残留无法清理。

## 目录结构

| 路径 | 语言 | 作用 |
| --- | --- | --- |
| `htdocs/luci-static/resources/view/homeproxy/{client,node,server,status}.js` | LuCI JS | 四个设置页面（客户端 / 节点 / 服务端 / 状态） |
| `htdocs/luci-static/resources/homeproxy/client/*.js` | LuCI JS | 客户端页面的各个 tab，一个 tab 一个文件（文件名即 tab id），各自导出 `render(s, ctx)`；`common.js` 放这些 tab 共用的小工具 |
| `htdocs/luci-static/resources/homeproxy.js` | LuCI JS | 前端共享模块：TLS / 传输层表单、校验器、证书上传等 |
| `root/etc/homeproxy/scripts/generate_client.uc` | ucode | 客户端配置生成入口：按固定顺序拼装各部分，`sing-box check` 后写出 `sing-box-c.json` |
| `root/etc/homeproxy/scripts/client/context.uc` | ucode | 一次性读取 UCI，生成 `ctx`：配置项、各类 tag 映射、需要 uci 的查询（`ctx.get_outbound()` 等），以及共享状态（`direct_overrides`、`http_clients`） |
| `root/etc/homeproxy/scripts/client/{dns,inbounds,outbounds,route}.uc` | ucode | 各自导出 `build(ctx)`，生成配置中对应的一节；`common.uc` 放纯解析函数和 `rule_match_fields()` |
| `root/etc/homeproxy/scripts/generate_server.uc` | ucode | UCI → `sing-box-s.json` |
| `root/etc/homeproxy/scripts/homeproxy.uc` | ucode | 后端共享模块：缺省值 `DEFAULTS`、命令执行、wget、URL/Base64 解析、TLS/传输层对象构建、校验 |
| `root/etc/homeproxy/scripts/parse_uri.uc` | ucode | 分享链接解析（每个协议一个函数） |
| `root/etc/homeproxy/scripts/update_subscriptions.uc` | ucode | 订阅拉取、校验、入库 |
| `root/etc/homeproxy/scripts/migrate_config.uc` | ucode | 升级时的 UCI 迁移（由 `uci-defaults/luci-homeproxy-migration` 调用） |
| `root/etc/homeproxy/scripts/firewall_post.ut` | ucode 模板 | 生成 fw4 nft 规则 |
| `root/etc/homeproxy/scripts/*.sh` | POSIX sh | kill switch、fw4 名称清单、缺省值（`defaults.sh`）、资源更新、日志清理 |
| `root/etc/init.d/homeproxy` | POSIX sh (procd) | 启动 / 停止 / 重载，jail 配置，dnsmasq 与 fw4 接入 |
| `root/usr/share/rpcd/ucode/luci.homeproxy` | ucode | 前端调用的 rpcd 接口（导入导出、证书、生成器、资源更新） |
| `root/etc/config/homeproxy` | UCI | 默认配置 |
| `po/templates/homeproxy.pot`、`po/zh_Hans/homeproxy.po` | gettext | 翻译模板与简体中文翻译 |
| `tests/` | — | 测试，详见 `tests/README.md` |
| `.github/build-pkg.sh`、`.github/workflows/` | bash / YAML | 打包（apk + ipk）、发布、i18n 与语法检查 |

数据流：**LuCI 表单 → UCI → `generate_*.uc` → sing-box JSON → `sing-box check` → procd 启动**；防火墙走 `firewall_post.ut` → fw4 include。

## 编码约定

- 缩进用 **Tab**，沿用所在文件的风格和命名。
- ucode 文件以 `'use strict';` 开头；ucode **不做变量提升**，使用前必须先声明（r12 和 r18 都栽在这里）。
- `client/` 下的模块用相对路径引用上级模块（`'../homeproxy.uc'`）：裸模块名是相对**当前文件所在目录**解析的。新增配置项读进 `context.uc` 的 `ctx`，不要在各 `build()` 里直接 `uci.get` 全局设置。
- 配置项缺省时的兜底值不要写成字面量：总表是 `homeproxy.uc` 的 `DEFAULTS`，ucode 直接读它；sh 用到的项在 `scripts/defaults.sh` 里以 `HP_DEFAULT_<OPTION>` 镜像一份，`tests/ucode/test_defaults.sh` 检查两边一致，`tests/frontend-defaults.js` 检查表单的 `o.default` 与它一致。缺省即关闭的开关不进表。
- 拼装顺序有依赖：`outbounds` 必须在 `route` 之前构建（后者读取前者记录的直连节点 override）。
- `init.d` 和 `scripts/*.sh` 在路由器上由 busybox `/bin/sh` 执行，只能写 **POSIX sh**，不要用 bash 语法。
- LuCI 视图用 `'require ...'` 引入依赖，用到 `ui` 等模块时别漏了 require。
- 注释保持克制：只解释“为什么”，不复述代码在做什么。新文件保留 SPDX 许可头。
- 前端多个页面共用的表单逻辑，放进 `homeproxy.js`（参考 `renderTlsOptions` / `renderTransportOptions`）；后端共用的逻辑放进 `homeproxy.uc`。不要复制粘贴。
- 安全：生成的配置文件权限保持 `600`；写入 nft 模板的值必须先校验（端口、mark、IP、MAC、接口名）；shell 拼接参数用 `shellQuote()`；日志里不要输出订阅 URL、密码等凭据。

## 界面文案与翻译

- 所有界面字符串都用 `_('...')` 包裹，**源文案写英文**。
- 每新增或修改一条 msgid，都要同步更新 `po/templates/homeproxy.pot` 和 `po/zh_Hans/homeproxy.po`。CI 要求 zh_Hans 覆盖率 **100%**：

  ```sh
  python3 tests/i18n-coverage.py --fail-below 100
  ```

- 不需要翻译的技术词（协议名、字段值）加进 `tests/i18n-ignore.txt`。
- 能联网时，可以用 `.github/rescan-translation.sh` 重新扫描生成 pot 并合并进 po。

## 测试

改完代码，至少跑下面这些能在本机运行的检查（CI 也会跑）：

```sh
# 语法检查
for f in root/etc/init.d/homeproxy root/etc/homeproxy/scripts/*.sh tests/*.sh tests/ucode/*.sh; do sh -n "$f"; done
for f in htdocs/luci-static/resources/homeproxy.js htdocs/luci-static/resources/view/homeproxy/*.js htdocs/luci-static/resources/homeproxy/client/*.js; do node --check "$f"; done

# LuCI 表单快照（只需要 node）
for v in node client server; do
	node tests/luci-form-snapshot.js . $v | diff -u tests/snapshots/$v.json - || echo "snapshot changed: $v"
done

# 翻译覆盖率
python3 tests/i18n-coverage.py --fail-below 100
```

ucode 测试包括 `parse_uri`、生成器 golden 快照加 `sing-box check`、kill switch 和 fw4。它们需要 ucode 和 sing-box ≥ 1.14：

- **CI**：`.github/workflows/test.yml` 在每次 push 到 main 和每个 PR 上，用 ImmortalWrt rootfs 容器跑完整套件（同时也跑表单快照）。推送前本地跑不了的部分，以 CI 结果为准。
- **本机有 Docker**：用 `tests/README.md` 里“In CI / with Docker”一节的命令，环境和 CI 一致。
- **路由器**：`HP_TEST_HOST=root@192.168.1.1 tests/run.sh`。

当前环境跑不了某项测试时，在汇报里说明哪些没跑、为什么，不要声称“已验证”。

规则：

- **快照变化必须是有意的。** 先看 diff，确认每一处都符合预期再重新生成；重新生成的命令见 `tests/README.md`。
- 新增分享链接格式 → 在 `tests/ucode/test_parse_uri.uc` 加用例。
- 新增会进入生成器的选项 → 扩展 `tests/fixtures/generators/*.uci`，并保持 schema 合法；client / server 的 golden 快照（`tests/snapshots/*.generated.json`）随之更新。
- 测试直接使用生产代码（必要时用 sed 改路径），不要再手写 mock 副本。
- 修 bug 时尽量先补一个能复现的用例。
- 不允许跳过、禁用或删除测试来换取通过。

## 提交与发布

- 提交信息用 Conventional Commits，**描述用中文**，scope 写模块名，例如：
  - `fix(client): 修复 DNS 服务器出站下拉列表保存后恢复直连`
  - `perf(init): 只改了节点/规则时用 SIGHUP 原地重载 sing-box`
  - `test(generators): 新增基于标签的 tag 回归用例`
  - `docs: ...`、`ci(build): ...`、`chore(release): bump to 27.919.1.14-rN`
- 一个提交只做一件事；重构和行为变更分开提交。
- 发布：只把 `Makefile` 里的 `PKG_RELEASE` 加 1，单独作为一个 `chore(release)` 提交；然后在 GitHub Actions 里手动触发 `Build` 工作流，`version` 填 `PKG_VERSION-rPKG_RELEASE`（例如 `27.919.1.14-r30`），必须与 Makefile 一致；留空则只构建、不发布。
- 用户能感知的变化，记到 `CHANGELOG.md` 最上面。
- `docs/`、`scratch/` 是本地工作目录（已在 `.gitignore` 中），里面的评审报告和计划**不要提交**。
