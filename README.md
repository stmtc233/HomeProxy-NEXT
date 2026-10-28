<div align="center">

# HomeProxy NEXT

**化繁为简的 sing-box 1.14 透明代理 · ImmortalWrt / OpenWrt**

不求功能多，只求够用；把现有功能做到足够好。

</div>

---

## 项目定位

HomeProxy NEXT 是一个**以自用为主**的 LuCI 代理模块，源自 [ImmortalWrt homeproxy](https://github.com/immortalwrt/homeproxy)，后经 [szwjp/homeproxy](https://github.com/szwjp/homeproxy) 的 sing-box 1.14 分支演进而来。

几条原则：

- **只认 sing-box ≥ 1.14**：直接生成 1.14 格式的配置，不做旧内核兼容。
- **少即是多**：不追新协议、不堆开关。新功能必须是日常真正用得上的，否则不加。
- **稳定优先**：优先修 bug、补测试、改善体验；改动以“行为不变、快照一致”为底线。
- **默认值开箱即用**：常见场景只需填好节点，不需要理解每一个 sing-box 字段。

> 包名、UCI 配置名、文件路径仍为 `luci-app-homeproxy` / `homeproxy`，与上游保持一致，方便直接覆盖安装和沿用旧配置。

## 功能

| 模块 | 内容 |
| --- | --- |
| **分流** | 路由节点（单节点、URLTest 自动选优、Selector 手动选择）、路由规则与规则集；规则可只在某些模式下生效，在 Dashboard 中切换模式不用重启 |
| **代理方式** | Redirect TCP、Redirect TCP + TProxy UDP、Redirect TCP + Tun UDP、Tun TCP/UDP |
| **节点** | AnyTLS、HTTP、Hysteria / Hysteria2、Shadowsocks、ShadowTLS、Snell、Socks、SSH、Trojan、TUIC、VLESS、VMess、WireGuard；urltest 自动选优 |
| **订阅** | 分享链接 / SIP008 导入，入库前校验，按订阅分组，可经代理更新 |
| **DNS** | 自定义 DNS 服务器与规则（同样可按模式生效）、乐观缓存、劫持 LAN DNS |
| **服务端** | 常用协议的 inbound，支持 ACME 证书 |
| **自定义插件** | 用 ucode 小脚本修改生成的 sing-box 配置，升级不会覆盖；可在界面上新增 / 编辑 / 启停 / 删除，见下文 |
| **其他** | Kill switch（客户端未运行时阻断海外流量）、sing-box 原生 Dashboard、配置导入 / 导出、规则清单自动更新 |

## 运行要求

- ImmortalWrt / OpenWrt ≥ 24.10（apk 或 opkg 均可安装）
- sing-box ≥ 1.14.0（低于 1.14 时服务拒绝启动，并在日志中说明原因）
- firewall4（nftables）

## 安装

从本仓库的 [Releases](../../releases) 下载对应包管理器的安装包（`luci-app-homeproxy-*.apk` 或 `*.ipk`，以及可选的 `luci-i18n-homeproxy-zh-cn-*`）：

```sh
# apk（ImmortalWrt / OpenWrt 25.x）
apk add --allow-untrusted luci-app-homeproxy-*.apk luci-i18n-homeproxy-zh-cn-*.apk

# opkg（24.10）
opkg install luci-app-homeproxy-*.ipk luci-i18n-homeproxy-zh-cn-*.ipk
```

安装后在 LuCI 的「服务 → HomeProxy NEXT」中配置。

## 自定义插件

想加一些只有自己用的定制，不要改 `/etc/homeproxy/scripts/` 下的生成脚本（升级会覆盖），写成插件放进 `/etc/homeproxy/custom/`。这个目录不属于安装包，升级不会动它，刷固件时也会保留。

- **管理**：在「自定义插件」页面新增、编辑、启用 / 停用、删除，点「应用」生效；也可以通过 SSH 直接改文件，然后执行 `/etc/init.d/homeproxy reload`。两边看到的是同一批文件。
- **启停**：`名字.uc` 为启用，`名字.uc.disabled` 为停用。多个插件按文件名顺序执行，例如 `10-xxx.uc`、`20-yyy.uc`。
- **写法**：脚本最后 `return` 一个对象。`client(config, ctx)` 拿到生成好的客户端 sing-box 配置，`server(config, ctx)` 拿到服务端配置，两者都在 `sing-box check` 之前调用。可以直接修改 `config`，也可以返回一个新对象；值设为 `null` 的字段会被去掉。客户端的 `ctx` 提供 `proxy_mode`、`ipv6_support` 和 `uci`（UCI cursor），服务端只有 `uci`。

  ```js
  'use strict';

  return {
  	client: function(config, ctx) {
  		// 插到最前面，优先于自带的分流规则
  		unshift(config.route.rules, { domain_suffix: [ 'example.com' ], action: 'route', outbound: 'direct-out' });
  	}
  };
  ```

- **出错时**：单个插件加载失败或执行时抛错，会跳过它并撤销它已做的修改，其余插件照常执行。加上插件后的配置通不过 `sing-box check` 时，服务改用不带插件的配置启动，保证网络可用。原因会写进 HomeProxy 日志，「自定义插件」页面也会显示每个插件的状态。
- **注意**：插件以 root 身份运行，能完全控制路由器，只添加你看得懂的代码。插件面对的是 sing-box 1.14 的配置格式（以 [sing-box 文档](https://sing-box.sagernet.org/) 为准），与 HomeProxy 的内部代码无关，所以 HomeProxy 升级后一般不用改。

## 已知限制

- DNS 劫持只重定向 UDP/53，使用 DoT / DoH 的客户端会绕过它（与 OpenWrt 原生 `dns_redirect` 行为一致）。
- 客户端运行时 dnsmasq 被配成 `no-resolv` 并转发给 sing-box，此时 DNS 服务器选 `system-dns` 会绕回 sing-box 自身，建议使用 `default-dns`。
- `update_via_proxy=0` 时，订阅更新期间服务处于停止状态；订阅多或源慢时停机时间会变长，需要零中断请开启 `update_via_proxy`。

## 开发

- 代码结构、约定与工作流程见 [AGENTS.md](AGENTS.md)（同时也是给 AI 编码助手的说明）。
- 测试说明见 [tests/README.md](tests/README.md)，入口为 `tests/run.sh`。
- 版本历史见 [CHANGELOG.md](CHANGELOG.md)。

<div align="center">

[![License](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](LICENSE) 版权归 ImmortalWrt.org 与各贡献者

</div>
