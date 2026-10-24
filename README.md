# v2rayNG · HarmonyOS NEXT 移植版

把 Android 的 [v2rayNG](https://github.com/2dust/v2rayNG)（2.3.13，Xray 内核）移植到鸿蒙原生（ArkTS/ArkUI）。

- **包名（新）**：`com.bosh.v2rayng`（应用名仍为 v2rayNG）
- **版本**：1.1.0 (101)，vendor=bosh
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
- 备份：节点 JSON 导出/导入（剪贴板）

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
