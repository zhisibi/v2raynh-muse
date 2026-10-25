# v2rayNG · HarmonyOS NEXT 移植版

把 Android 的 [v2rayNG](https://github.com/2dust/v2rayNG)（2.3.13，Xray 内核）移植到鸿蒙原生（ArkTS/ArkUI）。

- **包名（新）**：`com.bosh.v2rayng`（应用名仍为 v2rayNG）
- **版本**：1.2.0 (104)，vendor=bosh
- **Xray 内核**：v26.10.21（最新；tag commit 1b1647cd 的 pseudo-version 固定，Go 1.27 OHOS 工具链编译）
- **图标**：原版 v2rayNG 图标（白色背景，源图来自安卓工程 `ic_launcher-web.png`）
- **许可证**：随原项目 GPL-3.0

## 架构（文字版）

```
┌─ ArkUI (pages/Index 单页四 Tab) ─────────────────────────────┐
│  HomeTab 连接/测速/模式   ServersTab 节点   SubsTab 订阅   MineTab 设置 │
└──────────────┬───────────────────────────────────────────────┘
               │ model/（纯逻辑 + Preferences 持久化）
   UriParser(协议URI)  XrayConfig(JSON生成)  ServerStore  SettingsStore
   SubscriptionManager(HTTP拉取)  LogStore(内存+落盘日志)  CoreBridge(NAPI封装)
               │ service/
   ConnectManager(生成配置→写 xray_config.json→拉起扩展→轮询状态)
   VpnService(vpnExtension.startVpnExtensionAbility)
               │ VpnExtensionAbility（跨进程，状态走 vpn_status.json + vpn_diag.txt）
   V2RayVpnExtension: 建 TUN(双栈全路由) → attachTunFd → startXray → startTun(hev)
               │ cpp/xray_napi.cpp (libv2rayng_core.so, dlopen)
        libxray.so (Go c-shared: Xray-core)   libhevtun.so (hev-socks5-tunnel)
               │
   TUN 流量 → hev → SOCKS 127.0.0.1:10808 → Xray 出站 → 节点
```

对应 Android：Kotlin UI → MMKV 存储 → CoreConfigManager 生成 JSON →
LibXray（gomobile AAR）运行核心 → VpnService 建 TUN → hev-socks5-tunnel 转发。
鸿蒙侧一一对应，差异仅在 JNI→NAPI、VpnService→VpnExtensionAbility、MMKV→Preferences。

## 功能

- 协议：VMess（base64 JSON + URL 式）、VLESS、Shadowsocks（SIP002 + legacy）、Trojan、WireGuard（含 .conf 导入）、Hysteria2、SOCKS、HTTP 代理、CUSTOM 完整 JSON
- 订阅：添加/编辑/删除/手动与定时更新，`subscription-userinfo` 流量/到期解析，UA `v2rayNG/Harmony`
- 路由模式：规则（geoip/geosite cn 直连）/ 全局 / 直连；DNS 防泄漏分流
- TUN 全局模式（双栈、IPv6）与仅代理模式可切换；SOCKS 10808 / HTTP 10809
- 内置日志（老板铁律）：内存 + `filesDir/logs/v2rayng.log` 落盘 + 扩展诊断 `vpn_diag.txt`，日志页可导出（剪贴板 / 系统保存到文件）
- 扫码导入（Scan Kit）、全部测速（经核心 XrayPing 实测，可取消）、流量统计（核心 stats 累计字节）
- 按应用代理（基础版）：黑名单/白名单包名名单，TUN 建连时经 `vpn_perapp.json` 传给扩展
- 备份与恢复：节点+订阅+设置整体导出/导入（保存到文件 / 剪贴板，恢复二次确认）
- 界面（v1.2.0 对齐安卓版）：单页主界面（顶栏+分组标签+列表+底部连接栏）、节点二维码分享、路由设置页（自定义规则）、主题切换、启动自动连接、连接通知、geo 数据在线更新

## 构建

### 只打 HAP（UI/逻辑验证，核心未编译时为降级模式）

环境：JDK 17 + command-line-tools 5.1.0（API 18）。

```bash
export JAVA_HOME=~/ohos-build/jdk17
export PATH=$JAVA_HOME/bin:~/ohos-build/ohos-clt/command-line-tools/bin:$PATH
export DEVECO_SDK_HOME=~/ohos-build/ohos-clt/command-line-tools/sdk
export XDG_CONFIG_HOME=/tmp
echo "sdk.dir=$DEVECO_SDK_HOME" > local.properties
ohpm install
hvigorw assembleHap --mode module -p product=default -p buildMode=release
# 产物（未签名）：entry/build/default/outputs/default/entry-default-unsigned.hap
```

未签名 HAP 需在 DevEco Studio 自动签名后装机。

### 编译 Xray 核心（libxray.so，耗时较长）

```bash
export OHOS_NDK_HOME=~/ohos-build/ohos-clt/command-line-tools/sdk/default/openharmony/native
./scripts/build-ohos-core.sh   # 产物 entry/libs/arm64-v8a/libxray.so
```

`geoip.dat`、`geosite.dat` 已内置于 HAP rawfile，首启/连接前由 AssetInstaller 自动释放到应用数据目录 `files/xray_assets/`。

### hev TUN 转发（libhevtun.so）

```bash
./scripts/build-hevtun.sh      # 需 OHOS_NDK_HOME；产物 entry/libs/arm64-v8a/libhevtun.so
```

### 冒烟测试（纯逻辑）

```bash
bash tests/run-smoke.sh        # tsc strict 编译 UriParser/XrayConfig 后 Node 运行断言
```

## v1.1.0 完成状态

- **内核 v26.10.21**：Go 1.27 工具链（sysit/ohos-go `ohos-1.27-base` 自建 go1.27.1-ohos）重编 `libxray.so`，Xray* 全符号、TPREL=0；`coreVersion()` 运行时返回 “Xray 26.10.21 …”。
- **TUN 打通**：`libhevtun.so` 已落地——上游 hev-socks5-tunnel 全量源码（lwip/yaml/hev-task-system）以 OHOS NDK clang 按组件归档链接，适配层 `core/hev/hev_adapter.c` 以 pthread 包上游阻塞入口 `hev_socks5_tunnel_main_from_str`/`hev_socks5_tunnel_quit`，导出 `HevTunnelStart/HevTunnelStop`。TUN 模式下 startTun 失败会写 error 状态（step=tun-start），不再假报已连接。TUN 流量里的 UDP/53 由路由规则（socks 入站 → 内置 dns 出站）交给 Xray 内置 DNS 防泄漏处理。
- **真测速**：`XrayPing` 实现——未连接时起临时实例经该节点出站实测，连接中经运行实例入站测当前节点；UI 全部测速已接通（带进度/取消，失败回退 TCP）。
- **流量统计**：`XrayTraffic` 读运行实例 stats.Manager 的 proxy/direct 出站累计字节，Home 页展示累计上/下行。
- **扫码导入**：Scan Kit `startScanForResult`，需相机权限（已在 module.json5 声明）。
- **日志保存**：日志页新增「存文件」，系统保存选择器写入完整日志。
- **按应用代理（基础版）**：设置里选关闭/黑名单/白名单 + 包名名单。

## 已知限制 / 真机验证点

1. **真机未验证**：hev 在 OHOS TUN fd 上的实际转发（上游 set_offload 的 TUNGETIFF 等 ioctl 在鸿蒙 fd 上会失败但应被忽略）、protectProcessNet 防回环实效、VPN 授权流程、后台保活、WireGuard/Hysteria2 实际握手、扫码与保存选择器的真机表现——请按：TUN 连接后浏览器开外网、看 vpn_diag.txt 的 step 是否走到 running、日志页流量数字是否增长 来验收。
2. **libxray.so 未随仓提交**（.gitignore）：克隆仓库后需跑 `build-ohos-core.sh` + `build-hevtun.sh` 再打 HAP；没有 libxray.so 时 UI 可用但核心不启动（日志/状态明确报错）。
3. XrayPing 在已连接时只能测当前节点（临时实例入站端口与运行实例冲突），全部测速在连接中自动回退 TCP 直连并在提示中标注。
4. Go 桥 API 随 xray-core 大版本变化需按编译报错微调（v26 已适配 GetFeature/GetCounter 单返回值签名）。

详细逐项对照见 [docs/PORTING.md](docs/PORTING.md)。

## v1.1.1 诊断增强（数据面分段探针）

背景：v1.1.0 真机全 step 走完（tun-ok/protect/startXray/startTun 全部 true、状态 running）仍无法联网；生成配置已用官方 Xray 26.10.21 二进制验过 Configuration OK，问题在设备数据面。1.1.1 不改连接主流程，只加可观测性，一轮定位死在哪一段：

- **protect 真实回显**：`protectProcessNetDyn` 改返回 boolean，diag 打印 `protectProcessNet 结果=ok/缺失或失败`（此前静默失败也打「已调用」）。
- **hev 健康回显**：适配层新增 `HevTunnelRunning/HevTunnelLastRc`，NAPI 新增 `tunStatus()` 返回 `{"running":bool,"lastRc":int}`。
- **hev 日志落地**：yaml `misc.log-level: debug`；`startTun` 新增 logDir 参数，桥 setenv `HEV_LOG_PATH=<filesDir>/hev.log`，adapter 线程把 stderr 重定向到该文件；探针时尾部约 30 行并入 vpn_diag（`[hev.log]` 前缀）。
- **扩展分段探针**（TUN 连接成功后自动触发，只写 vpn_diag）：约 1 秒 tunStatus；约 3 秒节点探针（testDelay 实测 generate_204）+ tunStatus + **SOCKS 自检**（TCPSocket 手工 SOCKS5 握手/CONNECT/HTTP GET gstatic，读响应首行）；约 9 秒流量探针（queryTraffic 原文）+ tunStatus + hev.log 尾部。
- **日志页新增「VPN 诊断」区**：页内直接显示 vpn_diag.txt 全文（导出文本原本就含它，回传路径不变）。

探针判读表：

| 现象 | 指向 |
|---|---|
| `探针/tunStatus` running=false 或 lastRc≠-1（已退出） | hev 线程已死：看 [hev.log] 尾部的退出原因（配置/fd/ioctl） |
| 节点探针失败（-1）但 SOCKS 自检成功 | 不可能同时成立（自检本身经节点出站）——若出现，看 testDelay 临时/运行实例路径 |
| 节点探针失败 + SOCKS 自检失败（握手/CONNECT 异常） | Xray 核心出站段：节点本身、REALITY 参数、或核心出站被回环进 TUN（结合 protect 结果看） |
| SOCKS 自检成功（首行 HTTP/1.x 204）但浏览器不通 | 核心与节点没问题，问题在 TUN→hev 段或系统路由/DNS：看流量探针与 hev.log |
| 流量探针 up/down 全 0 且 SOCKS 自检成功 | TUN 侧没有流量进来：hev 未真正读 TUN fd 或路由未生效 |
| protect 结果=缺失或失败 | 防回环没生效，核心连节点的流量可能绕回 TUN 自环 |

## v1.1.2 修复（DNS 路由错抄根因）

1.1.1 真机探针回传定段：protect=ok、hev 线程活着、SOCKS 自检能连通核心但 HTTP 无响应、节点 testDelay=-1、流量 {}——**死在 Xray 出站段**。对照原版 `CoreConfigManager.kt` 实锤根因：我们的 DNS 路由是错抄的。

- **原版 DNS 架构**（对照 AppConfig/CoreConfigManager）：`dns.tag="dns-module"`，内部 DNS 模块产生的流量带 inboundTag `dns-module`；国内 DNS 服务器条目带 per-server tag（原版 `domestic-dns_0_0`，我们用 `dns-domestic`），domains=直连域名、skipFallback=true；路由有两条 DNS 专用规则 `{inboundTag:[domesticTags] → direct}`、`{inboundTag:["dns-module"] → proxy}`；hev 的 DNS 劫持是 `{inboundTag:["socks"], port:"53" → dns-out}` 插在最前。
- **我们的错误**：①一条无 inboundTag 的 catch-all `{port:"53" → dns-out}` 把内部 DNS 模块自己的上游查询（目的端口 53、inboundTag 为我们的 dns tag）也劫持进 dns 出站——解析递归/黑洞，节点域名与一切远程解析全死，出站自然无响应；②缺 `{inboundTag:[dns-module] → proxy}`；③TUN 下多造了一个 tag="dns" 的重复 dns 出站。
- **修复**：按原版重写 XrayConfig 的 DNS 段与规则顺序（tun 劫持 → dns-domestic→direct → dns-module→proxy → 模式规则），dns 出站只保留 `dns-out` 一个；冒烟断言同步锁定该形态（74 项），官方 Xray 26.10.21 二进制 `run -test` = Configuration OK。
- **内核日志回传**：Go 桥 XrayStart 在 LoadConfig 前改写 config 的 log 段——loglevel 不足 info 时提升为 info、error 日志落盘 `filesDir/xray_assets/xray_error.log`、access 禁用；扩展 9 秒探针把其尾部约 30 行以 `[xray.log]` 前缀并入 vpn_diag。真机若仍不通，回传日志页全文即可看到 Xray 出站/DNS 的真实报错。
- **流量探针判读改进**：XrayTraffic 失败分支不再统一返回 `{}`，改为 `{"error":"no-instance"|"no-feature"|"bad-type"}`，正常路径不变。

## v1.2.0 对齐（界面与功能对齐安卓版 v2rayNG）

主界面从四 Tab 改为安卓式单页：顶栏（标题/搜索/扫码/菜单）+ 订阅分组标签行 + 服务器列表 + 底部连接栏（连接键、选中节点、上下行流量、测试键）。核心链路（XrayConfig 的 DNS 架构、VpnExtension、Go 桥、C 桥）未动，唯一例外是按 F 项给 XrayConfig 增加了自定义规则注入点。

| 安卓版功能 | 鸿蒙状态 |
|---|---|
| 主界面（顶栏+分组标签+列表+底部连接栏） | 已对齐 |
| 节点列表行（选中标记/备注/协议·地址/延迟着色） | 已对齐 |
| 行操作（测速/编辑/分享链接/分享二维码/复制地址/删除确认） | 已对齐（长按或行尾 ⋮ 菜单） |
| 搜索过滤 + 排序（延迟/名称/添加时间） | 已对齐 |
| 二维码分享 | 已对齐（ScanKit generateBarcode 真实生成） |
| 扫码导入 | 已对齐 |
| 订阅管理（备注/域名/节点数/更新时间/用量/启停/更新全部带进度） | 已对齐 |
| 路由设置（模式 + 自定义域名/IP 规则） | 已对齐（基础版：五组多行文本，插入模式规则之前） |
| 应用设置分组（核心/VPN/订阅/界面/高级） | 已对齐 |
| 主题（跟随系统/浅色/深色） | 已对齐（ApplicationContext.setColorMode） |
| 启动自动连接 | 已对齐 |
| geo 数据更新 | 已对齐（下载 Loyalsoldier latest 覆盖 filesDir/xray_assets） |
| 备份与恢复（文件/剪贴板） | 已对齐（基础版：JSON 整体导出/恢复） |
| 连接状态通知 | 已对齐（基础通知，连接发/断开撤，id 1001） |
| 策略组 / 代理链 | 未做 |
| root 模式（TProxy 等） | 未做（鸿蒙无对应机制） |
| QS 磁贴 / 桌面小部件 | 未做 |
| Tasker 集成 | 未做 |
| 多语言完整 i18n | 未做（当前中文界面，字符串资源仅 App 名等少数条目） |
| WebDAV 备份 | 未做 |

## v1.2.1 修复（流量不动 + 节点测速无效）

v1.2.0 真机反馈：主界面、底部测试键、二维码均有效，但**底部流量不动、节点测速无效**。两条根因都在「进程」上——Xray 实例跑在 VPN 扩展进程，UI 进程里并没有核心实例：

| 问题 | 根因 | 修法 |
|---|---|---|
| 底部流量不动 | UI 进程调 native `queryTraffic()` 查的是本进程的 Go 全局实例（不存在），永远返回 `{"error":"no-instance"}`，总量恒 0；且原显示只统计 proxy 出站 | **跨进程流量文件**：扩展进程在连接成功后立即采样 + 每 2 秒采样（`queryTraffic()` 本进程解析，proxy 与 direct 分开记），写 `filesDir/vpn_traffic.json`（`{ts,up,down,proxyUp,proxyDown,directUp,directDown}`，带 TRUNC）；UI 每秒读快照显示 **proxy+direct 合计总量 + 差分速率**；停止时停采样并补写最终值；`ConnectManager.readTraffic()` 为统一读口，连接前删旧文件防串话 |
| 节点测速无效 | UI 侧测速被本进程 `isRunning()`（恒 false）挡住，永远走 TCP 直连握手兜底——UDP 类协议（Hysteria2/WireGuard/QUIC）必然失败、TCP 节点数值也不准；真正的 XrayPing 临时实例路径从未被调用，且它缺资产目录（规则模式 geo 规则加载失败）、与正式配置同用 10808/10809 端口 | **真实测速全链路**：`XrayConfig.buildXrayTestConfig()` 生成测速专用配置（入站固定 **18088/18089**、按非 TUN 生成无 DNS 劫持规则，同一生成逻辑加端口覆盖）；`testDelay` 全链路加第 4 参 `assetDir`（CoreBridge→NAPI→Go），Go 桥临时实例在 LoadConfig 前 Setenv `XRAY_LOCATION_ASSET/CONFIG` 并过 `rewriteLogConfig`（失败原因同时落 `xray_error.log`）；Go 侧 `pingMu` 串行化临时实例防抢测试端口；Index 删 TCP 兜底，失败原因经 `lastError()` 显示在界面并记日志；测速中行内显示「测速中…」，防重入，全部测速进度带成功/失败计数 |

细化：状态变 error 且界面无文案时自动带出扩展写入的失败原因；断开后速率清零。

### v1.2.1 真机验证清单

1. **流量**：TUN 模式连接后浏览网页/看视频约 10 秒，底部流量行总量应持续增长且速率随刷页面波动（有直连流量时也计入）；断开重连后总量从新会话重新累计。
2. **仅代理模式流量**：切换仅代理连接，流量同样应动。
3. **节点测速**：未连接状态下对单个节点点「测速」，应显示真实延迟毫秒数（不是秒回的 TCP 数字）；行延迟处测速中显示「测速中…」。
4. **UDP 类节点测速**：对 Hysteria2 / WireGuard 节点测速，应能测出延迟（旧版必失败）；不可达节点显示「测速失败：<原因>」。
5. **全部测速**：菜单「全部测速」，进度文案带累计成功/失败数，结束有总数统计；中途可取消。
6. **连接中测速**：保持连接时对列表里其它节点测速，结果正常且不影响当前连接；底部「测试」键测当前节点延迟正常。
7. **失败回传**：若仍有个别节点测速失败，应用日志（日志页「测速」条目）与 `xray_assets/xray_error.log` 应有具体原因。

## v1.2.2 修复（设置里很多选项点了不起作用）

v1.2.1 真机反馈：设置里很多选项点了不起作用。全量审计结论：多数设置的消费链路本是通的（端口/DNS/嗅探/UDP/TUN/按应用在生成配置时消费，自动更新间隔由回前台 `checkDue` 消费，自动连接在启动时消费），病灶集中在四处：

| 选项/范围 | 问题 | 修法 |
|---|---|---|
| 设置页 + 路由页几乎全部控件 | 开关（Toggle）、分段按钮、输入框只改 `@State`，落盘只发生在点右上「保存」或输入框回车时；拨完开关直接返回即全丢弃 | **即时保存**：两页所有 Toggle/分段改完 state 立刻静默保存（不弹 toast，页内 msg 提示「已保存 · 连接类设置重连后生效」）；输入框保留回车保存，另加 `aboutToDisappear()` 整页兜底保存；「保存」按钮保留。路由页模式分段即时存、五个规则编辑器离开页面兜底存 |
| 主题（跟随系统/浅色/深色） | 只调系统 `setColorMode`，而全应用颜色是 `Ui.ets` 的 `Pal` 硬编码浅色常量，自绘界面根本不变色（半死） | **双调色板**：`Ui.ets` 新增 `applyPalette(dark)`（深色值 bg `#12181D` 等）与 `resolveDark()`；`EntryAbility.onCreate` 在 `applyColorMode` 后按 `themeMode` 应用调色板，新增 `onConfigurationUpdate` 在跟随系统时响应系统深浅变化；设置页主题按钮保存后同步调用 `applyPalette` 并以 msg 变化触发本页重渲染立即变色 |
| 日志等级（warning/info/error） | Go 桥 `rewriteLogConfig` 把 warning/error 强升 info（v1.1.2 真机诊断遗留），三档实际一档（半死） | 删除强升逻辑：用户等级原样透传，仅缺失时补 `warning`（默认 warning 已含 error 级记录，出站/DNS 报错仍能落盘诊断）；error 落盘 `xray_error.log` 与 access 禁用保留。libxray.so 已重编 |
| IPv6 路由开关 | 只进了 XrayConfig 的 DNS `queryStrategy`；扩展的 VpnConfig 恒双栈、hev yaml 恒带 ipv6，扩展进程根本读不到这个设置（半死） | **全链路透传**：`VpnService.connect(tunEnabled, ipv6Enabled)` 经 want 参数 `v2rayng_ipv6`（`1`/`0`）进扩展；扩展关时 VpnConfig 仅 v4 地址/默认路由/DNS、`isIPv6Accepted=false`；`startTun` 加第 4 参 `ipv6`（CoreBridge→NAPI），桥侧 yaml 关时去掉 ipv6 行 |

文案：TUN/IPv6 说明末尾标注「（重连后生效）」，保存提示改为「设置已保存（连接类设置重连后生效）」。

### v1.2.2 真机验证清单

1. **即时保存**：设置页任意拨一个开关（如 UDP 转发）后直接返回、再进设置页，开关状态应保持；路由页改一条自定义规则不清保存直接返回，重进应还在。
2. **主题**：设置页切「深色」，本页应立即整体变深色；回主界面也已变色；切回「浅色」恢复；「跟随系统」时改系统深浅模式，应用跟随变化。
3. **日志等级**：设为 error 后重连，`xray_assets/xray_error.log` 不应再出现 info 级流水（仅错误）；设回 warning 为默认量级。
4. **IPv6**：关 IPv6 后重连（TUN），系统 VPN 信息/诊断日志应显示 `ipv6=false`，仅 IPv4 上网正常；开回后双栈恢复。
