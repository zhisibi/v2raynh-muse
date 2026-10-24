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
