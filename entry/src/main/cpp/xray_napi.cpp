/*
 * v2rayNG Harmony NAPI 桥
 *
 * 对应 Android 架构：
 *   - Kotlin 层经 gomobile 绑定的 Libv2ray/LibXray（AndroidLibXrayLite）调用 Xray-core；
 *     鸿蒙无 JNI/gomobile AAR，改为：Go 桥（core/xray-bridge）以 c-shared 编出
 *     libxray.so 并导出 C ABI，本文件 dlopen 后转成 NAPI。
 *   - Android 的 TUN 由 VpnService + hev-socks5-tunnel（独立进程读 TUN fd）完成；
 *     鸿蒙由 VpnExtensionAbility 建 TUN，本桥 attachTunFd 保存模板 fd，
 *     startTun 时 dup 一份交给 libhevtun.so（hev 的鸿蒙移植产物）。
 *
 * C ABI（core/xray-bridge/main.go 导出）：
 *   int         XrayStart(const char* configJson, const char* assetDir);
 *   void        XrayStop(void);
 *   const char* XrayVersion(void);
 *   const char* XrayLastError(void);
 *   int         XrayPing(const char* configJson, const char* url, int timeoutMs, const char* assetDir); // v1.2.1 起 4 参：临时实例需资产目录
 *   const char* XrayTraffic(void); // 可选符号，缺失时 queryTraffic 返回 {}
 *
 * hev C ABI（scripts/build-hevtun.sh 产物 libhevtun.so，适配层约定）：
 *   int         HevTunnelStart(const char* configYaml, int tunFd);
 *   void        HevTunnelStop(void);
 *   int         HevTunnelLastRc(void);   // v1.1.1 诊断（可选符号）
 *   int         HevTunnelRunning(void);  // v1.1.1 诊断（可选符号）
 * 符号缺失时 startTun 返回 false 并记录日志（上层降级为仅 SOCKS 代理可用）；
 * 诊断符号缺失时 tunStatus 返回 {"running":false,"lastRc":-999}。
 */
#include "napi/native_api.h"
#include "hilog/log.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <mutex>
#include <string>
#include <unistd.h>
#include <vector>

static constexpr const char *CORE_LIB_PATH = "libxray.so";
static constexpr const char *HEV_LIB_PATH = "libhevtun.so";
static constexpr const char *NAPI_LOG_TAG = "V2RayNapi";
static constexpr size_t MAX_TEXT_BYTES = 8 * 1024 * 1024;

using XrayStartFn = int (*)(const char *configJson, const char *assetDir);
using XrayStopFn = void (*)();
using XrayVersionFn = const char *(*)();
using XrayLastErrorFn = const char *(*)();
using XrayPingFn = int (*)(const char *configJson, const char *url, int timeoutMs, const char *assetDir);
using XrayTrafficFn = const char *(*)();
using HevStartFn = int (*)(const char *configYaml, int tunFd);
using HevStopFn = void (*)();
using HevLastRcFn = int (*)();
using HevRunningFn = int (*)();

static std::mutex g_mutex;
static void *g_core_handle = nullptr;
static XrayStartFn g_start = nullptr;
static XrayStopFn g_stop = nullptr;
static XrayVersionFn g_version = nullptr;
static XrayLastErrorFn g_last_error = nullptr;
static XrayPingFn g_ping = nullptr;
static XrayTrafficFn g_traffic = nullptr;

static void *g_hev_handle = nullptr;
static HevStartFn g_hev_start = nullptr;
static HevStopFn g_hev_stop = nullptr;
static HevLastRcFn g_hev_last_rc = nullptr;
static HevRunningFn g_hev_running = nullptr;

static std::atomic<int> g_tun_template_fd{-1};
static std::atomic<int> g_tun_mtu{1500};
static std::atomic<bool> g_running{false};
static std::atomic<bool> g_tun_running{false};

static bool loadCore() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_core_handle != nullptr) {
        return g_start != nullptr;
    }
    void *handle = dlopen(CORE_LIB_PATH, RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0, NAPI_LOG_TAG,
                     "libxray.so load failed: %{public}s", dlerror());
        return false;
    }
#define RESOLVE_REQ(var, name, type)                                          \
    do {                                                                      \
        var = reinterpret_cast<type>(dlsym(handle, name));                    \
        if (var == nullptr) {                                                 \
            OH_LOG_Print(LOG_APP, LOG_ERROR, 0, NAPI_LOG_TAG,                 \
                         "ABI symbol missing: %{public}s", name);             \
            dlclose(handle);                                                  \
            return false;                                                     \
        }                                                                     \
    } while (0)
    RESOLVE_REQ(g_start, "XrayStart", XrayStartFn);
    RESOLVE_REQ(g_stop, "XrayStop", XrayStopFn);
    RESOLVE_REQ(g_version, "XrayVersion", XrayVersionFn);
    RESOLVE_REQ(g_last_error, "XrayLastError", XrayLastErrorFn);
    RESOLVE_REQ(g_ping, "XrayPing", XrayPingFn);
#undef RESOLVE_REQ
    // 可选符号：流量统计
    g_traffic = reinterpret_cast<XrayTrafficFn>(dlsym(handle, "XrayTraffic"));
    g_core_handle = handle;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0, NAPI_LOG_TAG, "libxray.so loaded");
    return true;
}

static bool loadHev() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_hev_handle != nullptr) {
        return g_hev_start != nullptr;
    }
    void *handle = dlopen(HEV_LIB_PATH, RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0, NAPI_LOG_TAG,
                     "libhevtun.so load failed: %{public}s", dlerror());
        return false;
    }
    g_hev_start = reinterpret_cast<HevStartFn>(dlsym(handle, "HevTunnelStart"));
    g_hev_stop = reinterpret_cast<HevStopFn>(dlsym(handle, "HevTunnelStop"));
    if (g_hev_start == nullptr || g_hev_stop == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_WARN, 0, NAPI_LOG_TAG,
                     "hev ABI symbols missing (HevTunnelStart/HevTunnelStop)");
        dlclose(handle);
        return false;
    }
    // 可选诊断符号（v1.1.1）：缺失时 tunStatus 走 -999 降级
    g_hev_last_rc = reinterpret_cast<HevLastRcFn>(dlsym(handle, "HevTunnelLastRc"));
    g_hev_running = reinterpret_cast<HevRunningFn>(dlsym(handle, "HevTunnelRunning"));
    g_hev_handle = handle;
    return true;
}

static bool getUtf8String(napi_env env, napi_value value, std::string &out, size_t maxBytes) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok ||
        length > maxBytes) {
        return false;
    }
    std::vector<char> buffer(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied) != napi_ok ||
        copied != length) {
        return false;
    }
    out.assign(buffer.data(), length);
    return true;
}

static napi_value makeString(napi_env env, const char *value) {
    napi_value result;
    napi_create_string_utf8(env, value ? value : "", NAPI_AUTO_LENGTH, &result);
    return result;
}

static napi_value makeBool(napi_env env, bool v) {
    napi_value result;
    napi_get_boolean(env, v, &result);
    return result;
}

// ---- attachTunFd(fd, mtu): boolean ----
// 保存系统 TUN fd 的私有 CLOEXEC dup（模板），原始 fd 所有权仍归 VpnConnection。
static napi_value AttachTunFd(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t fd = -1;
    int32_t mtu = 0;
    bool ok = argc >= 2 && napi_get_value_int32(env, args[0], &fd) == napi_ok &&
              napi_get_value_int32(env, args[1], &mtu) == napi_ok &&
              fd >= 0 && mtu > 0 && mtu <= 65535;
    if (ok) {
        const int dupFd = fcntl(fd, F_DUPFD_CLOEXEC, 0);
        if (dupFd < 0) {
            ok = false;
        } else {
            const int old = g_tun_template_fd.exchange(dupFd);
            if (old >= 0) {
                close(old);
            }
            g_tun_mtu.store(mtu);
            OH_LOG_Print(LOG_APP, LOG_INFO, 0, NAPI_LOG_TAG,
                         "tun template fd attached, mtu=%d", mtu);
        }
    }
    return makeBool(env, ok);
}

// ---- startXray(configJson, assetDir): boolean ----
static napi_value StartXray(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string config, assetDir;
    if (argc < 2 || !getUtf8String(env, args[0], config, MAX_TEXT_BYTES) ||
        !getUtf8String(env, args[1], assetDir, 4096)) {
        return makeBool(env, false);
    }
    if (!loadCore() || g_start == nullptr) {
        return makeBool(env, false);
    }
    if (g_running.load()) {
        g_stop();
        g_running.store(false);
    }
    const int rc = g_start(config.c_str(), assetDir.c_str());
    g_running.store(rc == 0);
    OH_LOG_Print(LOG_APP, rc == 0 ? LOG_INFO : LOG_ERROR, 0, NAPI_LOG_TAG,
                 "XrayStart rc=%d", rc);
    return makeBool(env, rc == 0);
}

// ---- stopXray(): void ----
static napi_value StopXray(napi_env env, napi_callback_info info) {
    (void)info;
    if (loadCore() && g_stop != nullptr) {
        g_stop();
    }
    g_running.store(false);
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ---- isRunning(): boolean ----
static napi_value IsRunning(napi_env env, napi_callback_info info) {
    (void)info;
    return makeBool(env, g_running.load());
}

// ---- coreVersion(): string ----
static napi_value CoreVersion(napi_env env, napi_callback_info info) {
    (void)info;
    const char *value = "";
    if (loadCore() && g_version != nullptr) {
        const char *candidate = g_version();
        if (candidate != nullptr) {
            value = candidate;
        }
    }
    return makeString(env, value);
}

// ---- lastError(): string ----
static napi_value LastError(napi_env env, napi_callback_info info) {
    (void)info;
    const char *value = "";
    if (loadCore() && g_last_error != nullptr) {
        const char *candidate = g_last_error();
        if (candidate != nullptr) {
            value = candidate;
        }
    }
    return makeString(env, value);
}

// ---- queryTraffic(): string (JSON {"up":..,"down":..} 或 {}) ----
static napi_value QueryTraffic(napi_env env, napi_callback_info info) {
    (void)info;
    const char *value = "{}";
    if (loadCore() && g_traffic != nullptr) {
        const char *candidate = g_traffic();
        if (candidate != nullptr) {
            value = candidate;
        }
    }
    return makeString(env, value);
}

// ---- testDelay(configJson, url, timeoutMs, assetDir): number ----
// v1.2.1：assetDir 第 4 参透传给 Go 桥——临时实例 LoadConfig 前据此设置
// XRAY_LOCATION_ASSET，缺了它规则模式 geo 规则加载失败、测速恒 -1。
static napi_value TestDelay(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string config, url, assetDir;
    int32_t timeoutMs = 5000;
    int rc = -1;
    if (argc >= 4 && getUtf8String(env, args[0], config, MAX_TEXT_BYTES) &&
        getUtf8String(env, args[1], url, 2048) &&
        napi_get_value_int32(env, args[2], &timeoutMs) == napi_ok &&
        getUtf8String(env, args[3], assetDir, 4096) &&
        loadCore() && g_ping != nullptr) {
        rc = g_ping(config.c_str(), url.c_str(), timeoutMs, assetDir.c_str());
    }
    napi_value result;
    napi_create_int32(env, rc, &result);
    return result;
}

// ---- startTun(socksPort, mtu, logDir): boolean ----
// 从模板 fd dup 一份交给 hev；hev 配置 YAML 与 V2RayVpnExtension 的 TUN 地址保持一致。
// v1.1.1：第三个参数 logDir（filesDir）——拼出 <logDir>/hev.log 后 setenv
// HEV_LOG_PATH，hev adapter 线程据此把 stderr（debug 日志）重定向落盘。
static napi_value StartTun(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t socksPort = 10808;
    int32_t mtu = 1500;
    if (argc >= 2) {
        napi_get_value_int32(env, args[0], &socksPort);
        napi_get_value_int32(env, args[1], &mtu);
    }
    if (argc >= 3) {
        std::string logDir;
        if (getUtf8String(env, args[2], logDir, 4096) && !logDir.empty()) {
            const std::string logPath = logDir + "/hev.log";
            setenv("HEV_LOG_PATH", logPath.c_str(), 1);
            OH_LOG_Print(LOG_APP, LOG_INFO, 0, NAPI_LOG_TAG,
                         "HEV_LOG_PATH=%{public}s", logPath.c_str());
        }
    }
    const int templateFd = g_tun_template_fd.load();
    if (templateFd < 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0, NAPI_LOG_TAG, "startTun: no tun template fd");
        return makeBool(env, false);
    }
    if (!loadHev() || g_hev_start == nullptr) {
        return makeBool(env, false);
    }
    const int tunFd = fcntl(templateFd, F_DUPFD_CLOEXEC, 0);
    if (tunFd < 0) {
        return makeBool(env, false);
    }
    char yaml[1024];
    // 字段与上游 conf/main.yml 及安卓 v2rayNG 生成的 hev 配置对齐：
    // tunnel.name（外部 fd 时仅占位）、mtu、ipv4/ipv6 与 VpnConfig 的 TUN 地址一致；
    // socks5 指向 Xray 的 socks 入站（udp 走 udp 关联）。
    std::snprintf(yaml, sizeof(yaml),
                  "tunnel:\n"
                  "  name: tun0\n"
                  "  mtu: %d\n"
                  "  ipv4: 172.19.0.1\n"
                  "  ipv6: 'fdfe:dcba:9876::1'\n"
                  "socks5:\n"
                  "  port: %d\n"
                  "  address: 127.0.0.1\n"
                  "  udp: udp\n"
                  "misc:\n"
                  "  log-level: debug\n",
                  mtu, socksPort);
    // 注意：hev 以阻塞方式跑事件循环的版本需放独立线程；本桥约定 HevTunnelStart
    // 内部自建工作线程并立即返回（见 build-hevtun.sh 适配层说明）。
    const int rc = g_hev_start(yaml, tunFd);
    if (rc != 0) {
        close(tunFd);
    }
    g_tun_running.store(rc == 0);
    OH_LOG_Print(LOG_APP, rc == 0 ? LOG_INFO : LOG_ERROR, 0, NAPI_LOG_TAG,
                 "HevTunnelStart rc=%d", rc);
    return makeBool(env, rc == 0);
}

// ---- tunStatus(): string ----
// v1.1.1 诊断：返回 {"running":bool,"lastRc":int} JSON。
// running = hev 事件循环线程是否还活着；lastRc = 线程退出码（运行中 -1，
// 从未启动/诊断符号缺失 -999）。扩展用它在探针时点回显，区分假 running。
static napi_value TunStatus(napi_env env, napi_callback_info info) {
    (void)info;
    if (!loadHev() || g_hev_running == nullptr || g_hev_last_rc == nullptr) {
        return makeString(env, "{\"running\":false,\"lastRc\":-999}");
    }
    char buf[96];
    std::snprintf(buf, sizeof(buf), "{\"running\":%s,\"lastRc\":%d}",
                  g_hev_running() != 0 ? "true" : "false", g_hev_last_rc());
    return makeString(env, buf);
}

// ---- stopTun(): void ----
static napi_value StopTun(napi_env env, napi_callback_info info) {
    (void)info;
    if (g_tun_running.load() && loadHev() && g_hev_stop != nullptr) {
        g_hev_stop();
    }
    g_tun_running.store(false);
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"attachTunFd", nullptr, AttachTunFd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startXray", nullptr, StartXray, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopXray", nullptr, StopXray, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isRunning", nullptr, IsRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"coreVersion", nullptr, CoreVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"lastError", nullptr, LastError, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"queryTraffic", nullptr, QueryTraffic, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"testDelay", nullptr, TestDelay, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startTun", nullptr, StartTun, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopTun", nullptr, StopTun, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tunStatus", nullptr, TunStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

NAPI_MODULE(v2rayng_core, Init)
