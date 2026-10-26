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
| **分流模式** | 绕过中国大陆、仅代理中国大陆、GFWList、全局、自定义路由（路由节点 / 路由规则 / 规则集） |
| **代理方式** | Redirect TCP、Redirect TCP + TProxy UDP、Redirect TCP + Tun UDP、Tun TCP/UDP |
| **节点** | AnyTLS、HTTP、Hysteria / Hysteria2、Shadowsocks、ShadowTLS、Snell、Socks、SSH、Trojan、TUIC、VLESS、VMess、WireGuard；urltest 自动选优 |
| **订阅** | 分享链接 / SIP008 导入，入库前校验，按订阅分组，可经代理更新 |
| **DNS** | 国内外分流解析、自定义 DNS 服务器与规则、乐观缓存、劫持 LAN DNS |
| **服务端** | 常用协议的 inbound，支持 ACME 证书 |
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

## 已知限制

- DNS 劫持只重定向 UDP/53，使用 DoT / DoH 的客户端会绕过它（与 OpenWrt 原生 `dns_redirect` 行为一致）。
- `bypass_mainland_china` / `custom` / `global` 下 dnsmasq 被配成 `no-resolv` 并转发给 sing-box，此时选 `system-dns` 会绕回 sing-box 自身，建议使用 `default-dns`。
- `update_via_proxy=0` 时，订阅更新期间服务处于停止状态；订阅多或源慢时停机时间会变长，需要零中断请开启 `update_via_proxy`。

## 开发

- 代码结构、约定与工作流程见 [AGENTS.md](AGENTS.md)（同时也是给 AI 编码助手的说明）。
- 测试说明见 [tests/README.md](tests/README.md)，入口为 `tests/run.sh`。
- 版本历史见 [CHANGELOG.md](CHANGELOG.md)。

<div align="center">

[![License](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](LICENSE) 版权归 ImmortalWrt.org 与各贡献者

</div>
