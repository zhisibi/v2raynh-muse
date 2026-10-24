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
| hev-socks5-tunnel（独立进程） | `cpp` 内 `startTun/stopTun` + `scripts/build-hevtun.sh` | 适配层待补 |
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
2. **测速**：安卓版经核心 realping；鸿蒙版 v1 核心 ping 未实现，UI 用 TCP 直连并明确标注，核心 `XrayPing` 占位返回 -1。
3. **分应用代理/Root/TProxy/小部件/Tasker**：鸿蒙无对应机制或不在 v1 范围，未移植。
4. **更新检查/WebDAV 备份**：未移植；备份先走剪贴板 JSON。
5. **订阅格式**：仅 v2rayNG 风格 URI 列表（base64/明文）；Clash YAML 订阅不在 Xray 客户端原版能力内，同样不支持。

## 构建时需复核的 API 点（xray-core）

- `core.LoadConfig("json", reader)` / `core.New` / `Instance.Start/Close`：现版 API，若大版本变更按编译错误调整。
- `core.VersionStatement()`：版本字符串函数名以所用版本为准。
- `_ "github.com/xtls/xray-core/main/distro/all"`：全协议注册导入路径。
- hev 上游阻塞入口函数名与 stop 接口：写 `hev_adapter.c` 时以所克隆版本头文件为准。
