# 移植对照表（Android v2rayNG 2.3.13 → HarmonyOS NEXT）

## 文件对照

| Android（Kotlin） | HarmonyOS（ArkTS/C++/Go） | 说明 |
|---|---|---|
| `dto/entities/ProfileItem.kt` | `model/UriParser.ets` 内 `ProfileItem` | 字段同名同义；configType 改字符串枚举 |
| `fmt/VmessFmt.kt` | `UriParser.parseVmess/vmessToUri` | base64 JSON + URL 式两种 |
| `fmt/VlessFmt.kt` | `parseVless` / `toUri` | 含 reality 参数 pbk/sid/spx/pqv |
| `fmt/ShadowsocksFmt.kt` | `parseSs` | SIP002 + legacy + 明文 userinfo；plugin obfs=http |
| `fmt/TrojanFmt.kt` | `parseTrojan` | |
| `fmt/WireguardFmt.kt` | `parseWireguard` / `parseWireguardConf` | URI + .conf |
| `fmt/Hysteria2Fmt.kt` | `parseHysteria2` | obfs-password/mport/pinSHA256 |
| `fmt/SocksFmt.kt` | `parseSocks` | socks/socks4/socks5 |
| `fmt/FmtBase.kt` | `fillFromQuery/queryPairs/buildUri` | query 公共字段映射一致 |
| `dto/V2rayConfig.kt` | `model/XrayConfig.ets` | 以 JSON 对象组装后序列化 |
| `core/CoreOutboundBuilder.kt` | `XrayConfig.buildProxyOutbound/buildStreamSettings` | tcp/ws/grpc/xhttp/httpupgrade/kcp/quic、tls/reality |
| `core/CoreConfigManager.kt` | `XrayConfig.buildXrayConfig` | inbounds/dns/routing/policy/stats |
| `assets/v2ray_config.json` | `buildXrayConfig` 模板形态 | socks 10808 起 |
| `handler/MmkvManager`（节点） | `model/ServerStore.ets` | Preferences JSON |
| `handler/MmkvManager`（设置） | `model/SettingsStore.ets` | |
| `handler/SubscriptionUpdater.kt` | `model/SubscriptionManager.ets` | NetworkKit http |
| `dto/entities/SubscriptionItem.kt` | `SubscriptionManager.Subscription` | 含 userinfo 流量字段 |
| `service/CoreVpnService.kt` | `vpnextension/V2RayVpnExtension.ets` | VpnExtensionAbility 建 TUN |
| `service/*`（拉起/状态广播） | `service/VpnService.ets` + `service/ConnectManager.ets` | 状态文件跨进程同步 |
| AndroidLibXrayLite（gomobile） | `core/xray-bridge/main.go` + `cpp/xray_napi.cpp` | c-shared + NAPI 代替 JNI |
| hev-socks5-tunnel（独立进程） | `cpp` 内 `startTun/stopTun` + `core/hev/hev_adapter.c` + `scripts/build-hevtun.sh` | v1.1.0 已落地：同进程共享库 libhevtun.so，pthread 包上游阻塞入口 main_from_str/quit |
| `ui/main/*`（Compose） | `pages/Index.ets` + `components/{Home,Servers,Subs,Mine}Tab.ets` | 单页四 Tab |
| 节点编辑 Activities | `pages/EditServerPage.ets` | 按协议显隐字段 |
| `ui/logcat/*` | `pages/LogsPage.ets` + `model/LogStore.ets` | 新增落盘（安卓版无文件日志） |
| `ui/AboutActivity.kt` | `pages/AboutPage.ets` | |

## 协议支持矩阵

| 协议 | URI 解析 | URI 生成 | Xray 出站 | 备注 |
|---|---|---|---|---|
| VMess | ✅ base64+URL式 | ✅ | ✅ vmess | alterId 固定 0（与现版一致） |
| VLESS | ✅ | ✅ | ✅ vless | flow/reality 全参数 |
| Shadowsocks | ✅ SIP002+legacy | ✅ SIP002 | ✅ shadowsocks | obfs=http 映射 tcp http 头 |
| Trojan | ✅ | ✅ | ✅ trojan | |
| WireGuard | ✅ URI+.conf | ✅ | ✅ wireguard | address/peers/reserved/mtu |
| Hysteria2 | ✅（hy2:// 别名） | ✅ | ✅ hysteria v2 | obfs/udphop 经 finalmask 尽力映射 |
| SOCKS | ✅ | ✅ | ✅ socks | 含账密（明文/base64 userinfo） |
| HTTP(S) 代理 | ✅ | ✅ | ✅ http | https→tls |
| CUSTOM | ✅ JSON 直通 | ✅ | ✅ 原样 | 保存时校验 JSON |

## 与安卓版的行为差异（有意）

1. **日志**：安卓版靠 logcat；鸿蒙版内置日志页 + 落盘文件（装机排障要求）。
2. **测速**：v1.1.0 起 `XrayPing` 已实现（未连接起临时实例经节点出站实测；连接中经运行实例入站测当前节点，其余节点回退 TCP 并标注）。
3. **分应用代理**：v1.1.0 落地基础版（包名名单黑/白名单，经 VpnConfig 的 blocked/allowedApplications）；Root/TProxy/小部件/Tasker 鸿蒙无对应机制，未移植。
4. **更新检查/WebDAV 备份**：未移植；备份先走剪贴板 JSON。
5. **订阅格式**：仅 v2rayNG 风格 URI 列表（base64/明文）；Clash YAML 订阅不在 Xray 客户端原版能力内，同样不支持。

## 构建时需复核的 API 点（xray-core v26.10.21 已适配）

- 版本固定方式：tag `v26.10.21` 不能直接写 require（模块路径无 /v26 后缀），go.mod 用其 commit `1b1647cd` 的 pseudo-version `v1.260327.1-0.20261021115930-1b1647cd9ddf` 固定；该版 go.mod 要求 Go 1.27，工具链为 sysit/ohos-go `ohos-1.27-base` 自建的 go1.27.1-ohos。源码内 `core.Version_x/y/z = 26/10/21` 可核对。
- `core.LoadConfig("json", reader)` / `core.New` / `Instance.Start/Close`：v26 仍适用。
- v26 签名变化（已适配）：`Instance.GetFeature(t)` 只返回 1 个值；`stats.Manager.GetCounter(name)` 只返回计数器（缺失为 nil）。流量计数器名 `outbound>>>{tag}>>>traffic>>>{uplink|downlink}`，依赖配置 `policy.system.statsOutbound{Uplink,Downlink}=true` + `stats:{}`（XrayConfig 已生成）。
- `core.VersionStatement()` 返回 []string，桥内 join；运行时输出 “Xray 26.10.21 …”。
- `_ "github.com/xtls/xray-core/main/distro/all"`：全协议注册导入路径。

## v1.1.0 新增对照

| 功能 | 实现 | 备注 |
|---|---|---|
| TUN→SOCKS | `core/hev/hev_adapter.c` + `libhevtun.so` | 上游入口 `hev_socks5_tunnel_main_from_str`（阻塞）+ `hev_socks5_tunnel_quit`；fd 所有权归 hev（fini 时 close），adapter 不重复 close；外部 fd 路径会跳过 set_mtu/set_state，set_offload 的 ioctl 失败被忽略（真机验证点） |
| TUN DNS | `XrayConfig` TUN 分支 | 出站 tag=dns + 规则 inboundTag=[socks], network=udp, port=53 → dns；仅 TUN 模式 |
| 连接诚实报错 | `V2RayVpnExtension` | startTun 失败抛错，状态 error/step=tun-start；失败路径 teardown 不覆盖 error 状态 |
| 真测速 | Go 桥 `XrayPing` | 见上文测速条 |
| 流量 | Go 桥 `XrayTraffic` | 返回 up/down/upTotal/downTotal/directUp/directDown 累计字节 JSON |
| 扫码导入 | `ServersTab.scanImport` | ScanKit `scanBarcode.startScanForResult`；CAMERA 权限已声明；失败提示走剪贴板 |
| 日志保存 | `LogsPage.saveLogsToFile` | CoreFileKit picker `DocumentViewPicker.save` + fileIo 写入 |
| 按应用代理 | Settings/ConnectManager/扩展 | `vpn_perapp.json` 跨进程传配置；allow 模式设 allowedApplications 且清空 blocked |

## v1.1.1 诊断增强对照

| 项 | 文件 | 说明 |
|---|---|---|
| protect 回显 | `vpnextension/DynCompat.ts`、`V2RayVpnExtension.ets` | protectProcessNetDyn 返回 boolean；diag 打 `结果=ok/缺失或失败` |
| hev 健康 | `core/hev/hev_adapter.c` | 原子标志+退出码，导出 HevTunnelRunning/HevTunnelLastRc |
| tunStatus 桥 | `entry/src/main/cpp/xray_napi.cpp`、`model/CoreBridge.ets` | NAPI `tunStatus()` JSON；诊断符号缺失返回 lastRc=-999 |
| hev 日志 | 同上 + 扩展 | StartTun 第三参 logDir → setenv HEV_LOG_PATH；adapter dup2 stderr→hev.log；yaml log-level debug |
| 分段探针 | `V2RayVpnExtension.scheduleProbes/socksSelfCheck/dumpHevLogTail` | 1s tunStatus / 3s 节点+自检 / 9s 流量+hev.log 尾；纯 diag，不影响连接 |
| 诊断区 UI | `pages/LogsPage.ets`、`model/LogStore.readDiagText` | 页内展示 vpn_diag.txt，导出路径不变 |

## v1.1.2 修复对照

| 项 | 文件 | 说明 |
|---|---|---|
| DNS 架构重写 | `model/XrayConfig.ets` | dns.tag dns-in→dns-module；servers[0] 加 tag=dns-domestic（对照原版 domestic-dns_0_0）；删 tag=dns 的重复出站，只留 dns-out |
| 路由规则 | 同上 | 顺序：tun 时 {socks,53→dns-out}（无 network 字段）→ {dns-domestic→direct} → {dns-module→proxy} → 模式规则；删除 catch-all {port:53→dns-out}（递归黑洞根因） |
| 内核日志落盘 | `core/xray-bridge/main.go` | rewriteLogConfig：LoadConfig 前提升 loglevel 至 info、log.error=<assetDir>/xray_error.log、log.access=""；失败回退原 config |
| 流量失败标记 | 同上 | XrayTraffic 三个失败分支返回 {"error":"no-instance"/"no-feature"/"bad-type"} |
| xray 日志并入诊断 | `vpnextension/V2RayVpnExtension.dumpXrayLogTail` | 9 秒探针在 hev.log 尾部后追加 xray_error.log 尾部约 30 行（[xray.log] 前缀） |
| 冒烟断言 | `tests/smoke-main.ts` | dns.tag/servers[0].tag/规则前三条/无 catch-all/dns 出站唯一，74 项全过；官方二进制 run -test Configuration OK |

## v1.2.0 对齐对照

界面与功能对齐安卓版 v2rayNG（核心链路未动：XrayConfig 的 DNS 架构、VpnExtension、Go 桥、C 桥行为不变，唯一例外是自定义规则注入点）。

| 安卓版 | 鸿蒙实现 | 说明 |
|---|---|---|
| MainActivity 单页（顶栏+分组标签+列表+底部栏） | `pages/Index.ets` | 原四 Tab（components/HomeTab/ServersTab/SubsTab/MineTab）取消并删除：ServersTab 列表逻辑并入 Index，HomeTab 连接/流量/测试逻辑迁入 Index 底部栏 |
| 订阅设置页 | `pages/SubscriptionsPage.ets` | 由 SubsTab 迁移为独立页；域名由 URL 解析，subscription-userinfo 用量行，更新全部带进度文本 |
| SettingsActivity | `pages/SettingsPage.ets` | 由 MineTab 迁移：核心/VPN/订阅/界面/高级五组；geo 在线更新、coreVersion 运行时显示 |
| RoutingSettingActivity | `pages/RoutingPage.ets` | 模式三段与 customRules 五组文本（直连/代理/拦截域名、直连/代理 IP），存 SettingsStore 新字段 |
| 自定义规则注入 | `model/XrayConfig.buildXrayConfig` | 插到 DNS 三段规则之后、模式规则之前，顺序 拦截→直连→代理（域名组生成 domain 规则、IP 组生成 ip 规则），geosite:/geoip: 透传；冒烟新增 7 条断言锁定位置与 outboundTag，官方 Xray 二进制 run -test 复验 Configuration OK |
| 二维码分享 | `pages/QrSharePage.ets` | `@kit.ScanKit` generateBarcode.createBarcode 真实生成 PixelMap；失败降级 toast+复制链接 |
| BackupActivity | `pages/BackupPage.ets` | JSON{version,selectedId,servers,subscriptions,settings}，DocumentViewPicker 保存/选择文件 + 剪贴板双通道，恢复二次确认整体替换；Store 补 ServerStore.snapshotRaw/restoreRaw、SubscriptionManager.restoreAll，持久化 key 不变 |
| 连接通知 | `service/ConnectManager` | connect 成功后 NotificationKit publish 基础通知（id 1001，标题「v2rayNG 已连接」+节点名），disconnect 时 cancel；失败静默，未加额外权限声明 |
| 主题/自动连接 | `model/SettingsStore.applyColorMode` + `entryability/EntryAbility` | themeMode 存设置，onCreate 按之 setColorMode；autoConnect 开且有选中节点时 loadContent 后自动 connect，失败只记日志 |
| 策略组/代理链、root 模式、QS 磁贴/小部件、Tasker、完整 i18n、WebDAV | 未移植 | 鸿蒙无对应机制或超出基础对齐范围，如实记录 |

## v1.2.1 修复对照

v1.2.0 真机暴露两个跨进程缺陷，根因都是「Xray 实例在 VPN 扩展进程、UI 进程无实例」：

| 缺陷 | 根因 | 鸿蒙实现 |
|---|---|---|
| 底部流量不动 | UI 进程 native `queryTraffic()` 查本进程空实例，恒 `no-instance` | `vpnextension/V2RayVpnExtension` 连接成功后采样（立即+每 2s）写 `vpn_traffic.json`（proxy/direct 分开记、up/down 合计、TRUNC 写入、raw 带 error 时附 error 字段）；`service/ConnectManager.readTraffic()` 读快照，连接前 unlink 旧文件；`pages/Index.tickTraffic()` 6 秒新鲜度窗口 + 差分速率 + 连续 5 tick 无新鲜快照记一次日志；停止时扩展补写最终采样 |
| 节点测速无效 | UI 侧被本进程 `isRunning()` 恒 false 挡住永远走 TCP 握手兜底；XrayPing 临时实例缺 `XRAY_LOCATION_ASSET`、测试端口与正式端口相同 | `model/XrayConfig.buildXrayTestConfig()`（内部 `buildConfigWithPorts` 加端口覆盖：18088/18089 + 非 TUN 生成，CUSTOM 直通不变）；`testDelay` 全链路 4 参（`model/CoreBridge` → `cpp/xray_napi.cpp` argc=4 → Go `XrayPing(..., assetDir)`）；Go 桥临时实例 LoadConfig 前 Setenv + `rewriteLogConfig`、`pingMu` 整段串行、失败 `setErrText` 写明经哪个 HTTP 入站测速失败；Index 删除 TCP 兜底，`testNodeReal()` 统一入口（ensureAssets→测速配置→6000ms→失败取 lastError 记日志），行内「测速中…」+ 防重入 + 全部测速成功/失败计数；扩展节点探针同步补第 4 参 `assetDir()`（走运行实例路径） |

冒烟新增 7 条断言锁定测速配置形态（88 项全过）；测速配置经官方 Xray v26.10.21 二进制 `run -test` 复验 Configuration OK。

## v1.2.2 修复对照（设置有效性）

v1.2.1 真机反馈「设置里很多选项点了不起作用」。审计后四处定点修复，其余设置（端口/DNS/嗅探/UDP/TUN/按应用/自动更新/自动连接）消费链路原本即通，只是被保存问题拖累：

| 缺陷 | 根因 | 鸿蒙实现 |
|---|---|---|
| 设置页/路由页改动丢失 | 控件只改 `@State`，仅「保存」按钮/输入回车触发 `SettingsStore.save`，直接返回即丢弃 | `pages/SettingsPage`：新增 `silentSave()`（collect+save、仅更新 msg），全部 Toggle 与日志等级/按应用分段的回调在改 state 后调用；输入框保留 `onSubmit→save()` 并新增 `aboutToDisappear()` 兜底保存。`pages/RoutingPage`：抽 `persist()` 整页落盘，模式 segBtn 点击即调用，新增 `aboutToDisappear()` 兜底五个规则编辑器 |
| 主题不变色 | `SettingsStore.applyColorMode` 只设系统 ColorMode；界面全走 `components/Ui.ets` 的 `Pal` 硬编码浅色 | `Ui.ets` 新增 `applyPalette(dark)`/`resolveDark(mode, systemDark)` 双调色板（深色 bg `#12181D`/card `#1C262E`/text `#E8F0F4`/sub `#93A7B1`/accentSoft `#1E3448`/chip `#26343E`/line `#2E414D`，语义色共用）；`EntryAbility.onCreate` 在 applyColorMode 后应用、新增 `onConfigurationUpdate` 跟随系统变化（仅 system 模式）；SettingsPage 主题按钮经 `applyTheme()` 同步 applyPalette，msg 的 @State 变化触发本页重渲染 |
| 日志等级三档一档 | Go 桥 `rewriteLogConfig` 把 warning/error 强升 info（v1.1.2 诊断遗留） | `core/xray-bridge/main.go` 删除强升：loglevel 原样透传、缺失补 `warning`；error 落盘 `xray_error.log`、access 禁用保留；注释同步说明默认 warning 已含 error 级记录。libxray.so 已重编 |
| IPv6 开关进不了扩展 | 仅 XrayConfig DNS queryStrategy 消费；扩展 VpnConfig/hev yaml 恒双栈 | `service/VpnService.connect(tunEnabled, ipv6Enabled)`，want 参数 `PARAM_IPV6='v2rayng_ipv6'`（`1`/`0`，disconnect 传默认 true）；`vpnextension/V2RayVpnExtension` onCreate 解析存 `ipv6Enabled` 并 diag，VpnConfig 按之分双栈/仅 v4 两支（addresses/routes/dnsAddresses/isIPv6Accepted）；`model/CoreBridge.startTun` 加第 4 参，`cpp/xray_napi.cpp` StartTun argc=4 读 bool（缺省 true），yaml 关时去掉 `ipv6:` 行 |
