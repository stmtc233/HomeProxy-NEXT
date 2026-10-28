# 更新日志

HomeProxy NEXT 的版本号沿用 `27.919.1.14-rN`（`Makefile` 中的 `PKG_VERSION` / `PKG_RELEASE`）。
较新的条目在上；r14 之前的内容整理自原 README。

## 未发布

| 领域 | 变更 |
| --- | --- |
| **安装包** | 修复用 ipk 升级后 rpcd 仍在运行旧的 `luci.homeproxy` 接口：新加的资源（GeoSite 广告规则集）在资源管理里显示 not found、更新显示“未知错误”，直到重启 rpcd 或路由器。ipk 安装后现在和 apk 一样重新加载 rpcd |
| **路由规则** | 规则引用的规则集被删除或禁用后，在规则的编辑窗口里标红显示为“（已删除）/（已禁用）”，移除之前无法保存这条规则（之前只处理了单选的下拉列表） |
| **Dashboard** | 客户端页面顶部状态栏新增“打开面板”按钮（启用 Dashboard 时显示），在新标签页打开 sing-box 的面板；监听地址是 0.0.0.0 / :: 时用当前访问路由器的地址，只监听本机（127.0.0.1）时不显示 |
| **路由规则** | 「路由规则」「DNS 规则」每行新增“复制到”按钮：把规则复制到选定的路由模式（也可以是当前模式），目标模式里已有同名规则时名称自动加编号 |
| **路由规则** | 修复「路由规则」「DNS 规则」切换模式后，动作为“路由”的规则不显示出站 / 服务器列（r32 仍有此问题） |
| **路由模式** | 修复“加入模板模式”在模板模式的名称已被其他模式占用时（例如自己建了一个叫 Direct 的模式）仍然加入该模式，出现两个同名模式 |
| **客户端界面** | 出站、DNS 服务器、规则所属模式、默认模式等下拉选的分段被删除或禁用后，不再悄悄显示成第一项（例如直连）、保存时改掉原设置：下拉里保留原值并标为“（已删除）”或“（已禁用）”，标红，改选其他项之前整页无法保存 |
| **路由规则** | 修复「路由规则」「DNS 规则」里各行的出站、动作、DNS 服务器等显示成默认值（出站显示为直连）：表格只读取了打开页面时那一组规则的设置，显示的却是默认模式（或切换后的模式）的规则。此时保存或再次切换模式，会把这些默认值写回规则，规则的出站全部变成直连。请检查升级到 r31 后保存过的规则 |
| **翻译** | 修复节点与服务端 Hysteria2「Realm ID」格式不对时的提示一直显示英文：翻译文件里这条的双引号没有转义，LuCI 编译翻译时把它截断了。翻译覆盖率检查现在会拒绝含未转义引号的翻译文件 |
| **路由模式** | 开启“绕过中国流量”后不能使用名为 Global 的模式：中国大陆地址在防火墙里就绕过了 sing-box，Global 名不副实。生成配置时这个模式连同它的路由 / DNS 规则被略过（日志里提示），Dashboard 中也不再出现；默认模式是 Global 时改从第一个其他模式启动 |
| **默认模板** | 新装（或升级时还没有任何路由节点、路由规则、DNS 服务器、DNS 规则和规则集）时自动填入默认模板：四个路由模式——Rule（中国大陆域名和 IP 直连、屏蔽广告、其余走 Proxy）、RuleAllowAds（同 Rule 但不屏蔽广告）、Global（全部走 Proxy）、Direct（全部直连），默认 Rule，在 Dashboard 中切换；Proxy 是 Selector（可选 Auto＝所有节点的 URLTest、单个节点或直连），远程 DNS 8.8.8.8 走 Proxy、中国 DNS 223.5.5.5 直连，除 Direct 外都屏蔽 HTTPS / SVCB 记录。三个规则集从安装包自带的文件起步，首次启动不用下载，之后由 sing-box 每天更新。「路由模式」tab 里有“重置为模板”按钮，一键恢复（会替换路由模式和上述全部分段）。没有任何节点时客户端不启动 |
| **路由节点** | URLTest 和 Selector 的成员可以选“所有节点”：代表当前所有节点（包括以后订阅更新进来的），不用逐个勾选 |
| **资源列表** | 新增 GeoSite 广告规则集（sing-geosite 的 `geosite-category-ads-all`），和其他资源一样随安装包附带、在资源管理里显示版本并由资源更新刷新 |
| **资源列表** | 删除 GFW 列表和中国域名列表：只有已删除的简单路由模式用到它们。资源管理、定时更新和安装包里都不再有这两项 |
| **路由模式** | **不兼容变更，升级不迁移**：删除“绕过中国大陆”“仅代理中国大陆”“GFWList”“全局”四种简单路由模式，只保留原来的自定义路由（路由节点 / 路由规则 / DNS 规则 / 规则集）；不同的分流方式改用路由模式在 Dashboard 中切换。随之删除主节点 / 主 UDP 节点（含其 URLTest）、DNS 服务器与中国 DNS 服务器、CN-IP DNS 回退、“屏蔽 HTTPS/SVCB DNS 记录”（可用一条查询类型 64、65 → 拒绝的 DNS 规则代替）、访问控制里的“全局代理”设备和代理 / 直连域名列表、节点列表的“应用”按钮。旧的简单模式设置升级后不再生效；还没有自定义路由的配置升级时会自动填入默认模板（见上）。dnsmasq 始终把查询转给 sing-box；中国 IP 集合只在开启“绕过中国流量”时进防火墙，kill switch 始终放行中国大陆地址。插件的 `ctx` 不再有 `routing_mode` |
| **路由模式** | 新增「路由模式」tab：每个模式（sing-box 的 clash 模式，在 Dashboard 中切换，不用重启）有自己的路由规则和 DNS 规则，以及都没匹配上时的默认出站和默认 DNS 服务器，一条规则只属于一个模式。模式列表显示每个模式的规则数，可以改名、复制（连同规则）、删除（连同规则，删的是默认模式时默认改为剩下的第一个）和设为默认，还能“加入模板模式”：只补回模板中缺少的模式及其用到的路由节点、DNS 服务器和规则集，名称已被占用的模式不加。「路由规则」和「DNS 规则」顶部选择模式，下面只显示该模式的规则，新加的规则归入当前模式，在规则里也能改所属模式；所属模式被删掉的规则单独列出、不生效。「路由设置」的“默认模式”决定启动时的模式（选“禁用”则不启动客户端），在 Dashboard 切换过模式后，重启沿用切换后的模式；原来的“默认出站”和「DNS 设置」的“默认 DNS 服务器”移到各个模式里。**升级迁移**：已有的路由 / DNS 规则归入新建的模式「Custom」，沿用原来的默认出站和默认 DNS 服务器并设为默认模式（原来是“禁用”的仍不启动客户端），同时加入默认模板的模式（模板的分段名已被占用时不加，可用“重置为模板”）。配置总会带上不监听端口的 `clash_api`（sing-box 靠它提供模式） |
| **路由节点** | 新增 Selector（手动选择）类型：可选出站可以是节点、整个订阅、其他路由节点（含 URLTest 和其他 Selector）、直连或封锁，可设默认出站；在 Dashboard 中切换，选择结果在重启后保留。规则、DNS 服务器、规则集下载等的出站下拉里都能选它。Selector 互相嵌套成环时，表单和生成器都会拒绝（`sing-box check` 查不出这种环） |
| **资源列表** | 发布的安装包自带构建当天最新的资源（中国 IPv4/IPv6 列表，以及 GeoIP CN / GeoSite CN / GeoSite 广告规则集），装上即是最新，资源管理显示对应版本；之后由资源更新（定时或手动）刷新 |
| **资源管理** | 新增“全部更新”按钮：依次更新所有资源，汇总显示更新 / 已是最新 / 失败的数量；有资源更新且客户端在运行时，和定时更新一样立即应用新列表（防火墙集合），不用重启 |
| **DNS 缓存** | 修复「DNS 缓存」tab 的设置有时保存不上：同一组选项在隐藏的「DNS 设置」tab 里还有一份，LuCI 读到的是隐藏那份。现在这四项只在「DNS 缓存」tab 中；勾选“禁用 DNS 缓存”时乐观缓存与保存 DNS 缓存照旧隐藏 |
| **路由规则** | 修复“路由选项”动作同时勾选 TLS 分片与 TLS 记录分片时，sing-box 拒绝整份配置导致服务无法启动：表单阻止这种组合；已保存的旧配置在生成时保留 TLS 记录分片并在日志中提示。“路由”动作下两者可同时生效，行为不变 |
| **规则列表更新** | 下载依次尝试 fastly / gcore / cdn.jsdelivr 与 raw.githubusercontent.com 四个地址（同一 commit，内容一致），不再因单一 CDN 不可达而更新失败；日志记录实际使用的镜像 |
| **状态栏** | 客户端与服务端状态增加黄色“状态未知”：查询失败（重启过程中、登录过期）时不再误报“未运行”；两个页面改用 `homeproxy.js` 中共用的状态函数 |
| **订阅分组** | 修复前端 MD5 对 emoji 等 BMP 以外字符计算错误：订阅 URL 含 emoji 时，前端写入的 `sub_<hash>` 分组与后端对不上，会被订阅更新当作“已删除”清掉 |
| **自定义插件** | 新增「自定义插件」页面：在 `/etc/homeproxy/custom/` 放 ucode 小脚本修改生成的 sing-box 配置，升级不覆盖、刷固件保留；界面可新增 / 编辑 / 启停 / 删除，与直接改文件同步。单个插件出错会被跳过；加上插件后配置通不过检查时，按不带插件的配置启动 |
| **缺省值** | 配置项缺省时的兜底值集中到 `homeproxy.uc` 的 `DEFAULTS`（sh 侧镜像在 `scripts/defaults.sh`）。`infra` 段的兜底值改为与出厂配置一致：缺少 `ntp_server` 时不再默认启用 time.apple.com 的 NTP（与迁移脚本一致），缺少 `common_port` 时的“常用端口”补上 5222。配置里缺少 `ipv6_support` 时，表单的“IPv6 支持”改为不勾选，与后端按关闭处理一致（出厂配置仍为开启） |

## r14 – r29

| 领域 | 变更 |
| --- | --- |
| **启动与重载** | 重载时只重做有变化的部分；只改了节点 / 规则时用 SIGHUP 原地重载 sing-box；LuCI 只在 homeproxy 有改动时立即刷新，跳过固定等待 |
| **客户端界面** | 状态栏增加“重启”按钮；修复 DNS 服务器出站等下拉列表保存后回到直连、丢失最后一项且包含自身的问题；出站 / DNS 服务器 / 规则集 tag 改用标签而不是 UCI 段名 |
| **Kill switch** | sing-box 客户端未运行时阻止海外流量 |
| **DNS** | 自定义 DNS 新增 `dhcp`、`hosts` 服务器类型与 `respond` 动作 |
| **节点** | Hysteria2 支持 Realm；urltest 支持按订阅分组，可整组订阅加入 |
| **Dashboard** | 改用 sing-box 1.14 原生 `api` 服务（不再使用 Clash API），文件放内存 `/var/run/homeproxy/dashboard`，修复 jail 内无法写 `/tmp` |
| **配置备份** | 状态页支持配置导入 / 导出，可选是否包含节点与订阅 |
| **修复** | #10 自定义分流配置全量丢失（r14）；独立 UDP 节点规则被 `geoip-cn` 抢先终局；订阅更新声明顺序报错与 urltest 默认参数缺失 |
| **CI** | 发布支持预发布标记，并以当前提交为 tag 目标 |

## r4 – r13

### 已融入的 sing-box 1.14 特性

| 领域 | 特性 |
| --- | --- |
| DNS | `evaluate` / `match_response` / `race` 响应匹配，乐观缓存与 `store_dns`，统一 `dns.timeout` |
| 规则集 | `initial_path`、多 tag、`http_clients` 下载客户端 |
| 连接 | TUN `dns_mode` / `dns_address`，UDP NAT 参数（`udp_mapping` / `udp_filtering` / `udp_nat_max`） |
| 证书 | `tls.acme` → `certificate_provider`（`key_type` / `profile` / `account_key`） |
| 工程化 | 生成配置内置 `$schema`；运行要求 sing-box ≥ 1.14 |

### 已修复：国内域名走代理问题（r4 / r6 / r7）

**背景**

`bypass_mainland_china` 的数据路由原本只用 `geoip-cn`（按 IP 匹配国内目标）。sing-box 不会把「域名连接」的域名解析成 IP 再去匹配 IP 规则集，因此按域名访问的国内站（如字节、百度等）落到 `main-out` 走了代理，只有「裸 IP 访问国内 IP」才直连。

**修复方式**

数据路由改用 `action: resolve (prefer_ipv4)` + `geoip-cn → direct-out`——先解析域名再做 IP 匹配，由真实 IP 决定国内 / 国外（国内 IP → 直连，其余 → 代理）；数据判定不再依赖 `geosite-cn` / `geosite-noncn` 域名规则（`geosite-cn` 仍用于 DNS 路由）。

对字节、百度等国内域名，以及苹果等全球跨国企业站点更稳更友好；默认使用公共 DNS（223.5.5.5）作为国内 DNS 以降低污染概率。

**可选增强 `cn_ip_fallback`**

启用后使用 1.14 原生 `evaluate` / `match_response`：对非 `geosite-cn` 域名，若 `main-dns` 返回国内 IP，再回退到 `china-dns` 解析。

> 这版块确实很难两全，改来改去也都存在缺憾，就这样不改了，照顾大多数为准。

### 新增：Dashboard 支持（sing-box 1.14 原生 API）

在「客户端设置 → 路由设置」中可启用 sing-box 1.14 的 `api` 服务（`services` 中 `type: api`，不使用 Clash API）：

- 监听地址默认 `0.0.0.0:9090`（仅本机访问可改为 `127.0.0.1:9090`），建议同时设置密钥；
- 网页 Dashboard 由 sing-box 下载到 `/var/run/homeproxy/dashboard/web` （内存中，重启后重新下载）并每天刷新，下载走主节点（未设置主节点则直连）；可自定义 ZIP 下载地址，留空使用 sing-box 默认 Dashboard；
- 启用后通过 `http://路由器地址:9090/dashboard/` 访问，sing-box 官方客户端也可用该地址远程控制。

### 新增：规则集自动更新（r5）

为 `bypass_mainland_china` 的三个远程规则集（`geoip-cn` / `geosite-cn` / `geosite-noncn`）增加 `update_interval: '24h'`，sing-box 每 24 小时自动重新拉取 `.srs`：

- 热替换，不中断既有连接；
- 下载失败时保留旧规则集，不影响分流。

### 新增：Snell 协议与 Hysteria2 增强（r9）

面向 sing-box 1.14 的一轮收敛：补齐新协议、暴露传输层新参数，并修复 1.14 DNS 迁移的一个行为缺陷。

| 领域 | 变更 |
| --- | --- |
| **Snell（1.14 新协议）** | 客户端出站 + 自建服务端 inbound 全支持（v4 / v6、psk、多用户 `userkey`、HTTP 混淆、v6 流量整形）；订阅导入 `snell://` |
| **Hysteria2** | 新增 `disable_chrome_parrot`（Ed25519 证书服务器兼容开关）、`bbr_profile`、`hop_interval_max`（跳变间隔随机化）、`gecko` 混淆与 min/max 包长；服务端同步支持 gecko |
| **Hysteria v1** | 移除上游已废弃的 QUIC 流控调参（上游 1.16 将删除），回归 sing-box 默认 |
| **DNS** | 修正 1.14 自动迁移：legacy `ip_cidr` / `ip_is_private` 包装 `evaluate` 时继承原规则查询条件，不再对全部查询预解析 |
| **连接与交互** | TLS `handshake_timeout`；TUN `dns_mode` 缺省（hijack）与平台 DNS 劫持叠加的界面指引；规则集 merged / OR 匹配语义与 `query_type` 兼容性提示 |

> 设计取舍：Chrome QUIC 指纹（1.14 默认开启）仅在服务器证书为 Ed25519 等握手失败时才需关闭；Snell 采用 sing-box 官方实现（v5 无线协议视同 v4，不支持 v5 QUIC 代理模式）。

### 新增：规则分流与 TLS 能力补全（r10）

补齐 sing-box 1.14 在路由规则与规则集加载侧的剩余能力，并加固一处规则集配置的校验提示。

| 领域 | 变更 |
| --- | --- |
| **route `resolve`** | 新增 `disable_optimistic_cache`、`timeout`两个控件,乐观缓存增至四个选项 |
| **route / route-options** | 新增 `tls_spoof` / `tls_spoof_method`（注入伪造 ClientHello 干扰按 SNI 过滤的中间盒，需特权），LuCI 提供 SNI 与方式选择（默认 wrong-sequence） |
| **规则集加载** | 多 tag 时若 `path`/`url`/`initial_path` 缺少 `{tag}` 占位，生成器给出 `warn` 提示，配合 LuCI 表单校验与 sing-box 的硬拒绝（`missing {tag} placeholder`），三层防护避免误配 |
| **i18n** | 补齐新增文案的 zh_Hans 译文 |

### 工程化加固（r11）

一轮以可维护性与可验证性为目标的加固：重构不改变行为，测试锁住结果，经实机验证。

| 轮次 | 做了什么 | 结果 |
| --- | --- | --- |
| 重构和修复错误 | 重构：前端 TLS/传输表单收敛、generator 共享 TLS/transport 构建、`parse_uri` 拆为 13 个协议函数<br>测试：协议单测 153 条、generator 回归、LuCI 表单快照<br>修复：`executeCommand` 清理、dnsmasq 路径告警、fw4 清单单源、启动日志、PEM 校验、`wGET` 失败原因<br>工程：提高中文翻译率 CI、架构核实 | <br>parse_uri 对比零差异、generator JSON 逐字节一致、表单快照逐字段一致<br>顺带修复 3 个既有缺陷：证书上传、fw4 清理回滚、dnsmasq 路径 |

### 稳定性修复（r12）

修掉两个会让功能整体不可用的缺陷，均由 issue 复现确认。

| 领域 | 变更 |
| --- | --- |
| **订阅抓取**（#5） | 抓取前先探测 wget 实现：GNU wget 用 `-nv`（静音进度条但保留失败原因），uclient-fetch / busybox wget 用 `-q`；`--user-agent` / `--timeout` 一并换成三家通用的 `-U` / `-T`。r11 引入的 `-nv` 是 GNU 专有选项，而 OpenWrt / ImmortalWrt 的 `/usr/bin/wget` 默认由 uclient-fetch 提供，参数解析阶段即失败，导致所有订阅更新以 `no valid node found` 结束 |
| **自定义路由**（#3 #4） | 修复 `routing_mode='custom'` 完全无法生成配置：`direct_overrides` 的使用早于声明（ucode 不做变量提升，strict 模式下直接抛未声明变量）；本地规则集残留 legacy `download_detour` 字段，被 sing-box 判为 `unknown field` 而拒绝整个配置 |
| **预设规则集** | `geoip-cn` / `geosite-cn` / `geosite-noncn` 改用 SagerNet 上游 raw URL，并经 `main-out` 下载：直连受 DNS 污染时会超时并静默沿用缓存；每天约 250 KB 的代理开销可忽略，节点引导不受影响 |
| **依赖** | Makefile 补上 `+ip-full`、`+kmod-tun` |

> 回归保障：订阅抓取用 stub wget 覆盖 GNU / 非 GNU 两条分支，并在装有 `/bin/uclient-fetch` 的目标上直接执行生成的命令行；自定义路由新增 `custom.uci` fixture（本地规则集 + 直连节点覆盖 + 路由规则）。

### 安全与可用性修复（r13）

一轮以"资源/订阅链路真正生效"和"收敛暴露面"为目标的修复，全部结论都做了实机或本地复现。

| 领域 | 变更 |
| --- | --- |
| **资源更新生效** | `update_resources.sh` 的 `--header-file=` 改为 `--header=`——uclient-fetch 与 GNU wget 都不认 `--header-file`，填了 GitHub token 时四个清单的版本探测会全部失败；新增 `/etc/init.d/homeproxy refresh_lists`，清单下载后重建 fw4 集合与 dnsmasq 片段（此前 cron 只改磁盘文件，只有订阅更新"顺带"重启时才真正生效） |
| **规则集** | 删除无人引用的 `geosite-noncn`（sing-box 会初始化每一个声明的远程规则集，引用与否都会下载、失败即拒绝启动）；`geoip-cn` / `geosite-cn` 在本地 `.srs` 存在时生成为 `type: local`，否则回退远端——cron 经 jsdelivr 固定 commit 下载，冷启动不再依赖"经节点拉 CDN" |
| **订阅与导入** | 入库前按协议校验必需字段并跳过坏节点（此前一个坏节点会让整份配置生成失败、看似更新成功却一直跑旧配置）；`flow` 只保留 `xtls-rprx-vision`；SS userinfo 先做百分号解码（`%3D` 不再丢 method/password）；`simple-obfs` 归一化为 `obfs-local`；不支持的 transport（xhttp 等）直接跳过；订阅更新加 mkdir 锁；`update_via_proxy=1` 时配置变更也会重启；日志中的订阅 URL 脱敏 |
| **暴露面** | 生成的客户端/服务端配置权限改为 600（含全部节点凭据）；capabilities 去掉 `CAP_SYS_PTRACE` / `CAP_NET_RAW`；`dns-in` 只监听 `127.0.0.1`（此前 LAN 内可把它当解析器用）；custom 路由模式也进 ujail；core dump 关闭（`core=0`） |
| **DNS** | `dns.servers[].headers` 由界面列表转成 1.14 要求的 map（此前填 Headers 会让整份配置非法）；`action: route` 缺 server 的 DNS 规则跳过并告警；`tls_fragment_fallback_delay` 单位修正为毫秒（原先被当成秒，放大 1000 倍）；新增 `block_https_rr` 开关（默认仍拦截 HTTPS/SVCB，需要 ECH 时关闭） |
| **健壮性** | 大响应不再被单次 512 KiB 读取截断；防火墙模板对端口/mark/IP/MAC/接口名逐一校验（非法值不再让之后每次 `fw4 reload` 都失败）；`isValidCIDR` 严格校验前缀，堵住远程清单注入 nft 模板的路径；生成失败按退出码报错而不是沿用旧配置；`log()` 先建目录，首启诊断不再丢 |
| **验证** | 新增 client 表单快照、client 生成 golden 快照（逐字节锁定生成结果）、700 KiB 读取与 CIDR 注入用例；CI 增加 shell/JS 语法检查，i18n 覆盖率由 warn 改为 fail |

> 有意未改动的项：订阅抓取仍在 `update_via_proxy=0` 时先停服（这是该选项的定义，改抓取时序会改变抓取路径）；`tls_self_sign`、`hysteria_protocol` 与 `ssh_priv_key` 的 DynamicList 展示保持与 `-pro` 分支一致，留待两线一起收敛。
