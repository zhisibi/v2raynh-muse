# v2rayNG · HarmonyOS NEXT 移植版

把 Android 的 [v2rayNG](https://github.com/2dust/v2rayNG)（2.3.13，Xray 内核）移植到鸿蒙原生（ArkTS/ArkUI）。

- **包名（新）**：`com.bosh.v2rayng`（应用名仍为 v2rayNG）
- **版本**：1.0.0 (100)，vendor=bosh
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
- 内置日志（老板铁律）：内存 + `filesDir/logs/v2rayng.log` 落盘 + 扩展诊断 `vpn_diag.txt`，日志页可导出（剪贴板）
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

另需把 `geoip.dat`、`geosite.dat` 放到真机应用数据目录 `files/xray_assets/`（或后续版本内置到 HAP rawfile 并首启释放，真机迭代项）。

### hev TUN 转发（libhevtun.so）

```bash
./scripts/build-hevtun.sh      # 适配层未补齐前会明确报错；不影响 SOCKS 代理使用
```

### 冒烟测试（纯逻辑）

```bash
bash tests/run-smoke.sh        # tsc strict 编译 UriParser/XrayConfig 后 Node 运行断言
```

## 已知限制 / TODO（真机项）

1. **libxray.so 未随仓编译**：需跑 `build-ohos-core.sh`（OHOS Go fork 编 Xray，数十分钟）。没有它时 UI 完整可用但核心不启动（日志与状态会明确报错）。
2. **hev 适配层**：`hev_adapter.c` 未写，TUN→SOCKS 转发未生效；当前 TUN 建好、核心起来后，系统级流量转发待该库补齐。SOCKS/HTTP 本地代理不受影响。
3. **XrayPing/XrayTraffic 为占位**：Go 桥 v1 返回 -1 / `{}`；UI 测速回退 TCP 直连，流量显示为 0。后续经 core stats API 补齐。
4. **geoip/geosite 资产**：路由规则引用 `geoip:cn` 等类别，需 dat 文件就位，否则核心启动报错（日志可见）。
5. **扫码导入**：未接 Scan Kit（TODO 占位），先用剪贴板/粘贴导入。
6. **日志导出**：现走复制剪贴板 + 落盘路径；系统保存/分享（picker/ShareKit）待补。
7. **真机未验证项**：VPN 授权流程、protectProcessNet 防回环实效、hev 接入后端到端流量、后台保活、WireGuard/Hysteria2 实际握手。
8. Go 桥 `core.VersionStatement()` 等 API 名以构建时 xray-core 版本为准，编译若报 API 变更按报错调整（见 docs/PORTING.md）。

详细逐项对照见 [docs/PORTING.md](docs/PORTING.md)。
