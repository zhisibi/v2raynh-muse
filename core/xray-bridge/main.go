// v2rayNG Harmony · Xray 核心 Go 桥（c-shared）
//
// 对应 Android：AndroidLibXrayLite（gomobile bind 出 AAR，Kotlin 调 LibXray）。
// 鸿蒙路线：OpenHarmony Go fork 编 -buildmode=c-shared 出 libxray.so，
// 导出下列 C ABI 给 entry/src/main/cpp/xray_napi.cpp 经 dlopen 调用。
//
// 依赖版本：github.com/xtls/xray-core v26.10.21（go.mod 固定，要求 Go 1.27）。
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	_ "github.com/xtls/xray-core/main/distro/all" // 注册全部协议/传输/路由实现
)

var (
	mu            sync.Mutex
	instance      *core.Instance
	runningConfig string // XrayStart 成功时的配置原文（XrayPing 解析运行实例入站端口用）
	lastErr       string
	// pingMu 串行化 XrayPing 的临时实例路径：临时实例抢占固定测试端口，
	// 并发 ping 会互相冲突，必须整段串行（v1.2.1）。
	pingMu sync.Mutex
)

func setErr(err error) {
	mu.Lock()
	defer mu.Unlock()
	if err == nil {
		lastErr = ""
	} else {
		lastErr = err.Error()
	}
}

func setErrText(s string) {
	mu.Lock()
	defer mu.Unlock()
	lastErr = s
}

func cString(s string) *C.char {
	return C.CString(s)
}

// snapshotInstance 取当前运行实例与配置（短临界区，调用方不得在持锁时用）。
func snapshotInstance() (*core.Instance, string) {
	mu.Lock()
	defer mu.Unlock()
	return instance, runningConfig
}

// rewriteLogConfig 在 LoadConfig 前改写 config 的 log 段（v1.1.2）：
// loglevel 为 warning/error（或缺失）时提升为 info，让真机故障能在
// xray_error.log 里留下出站/DNS 的实际报错；error 日志落盘到
// assetDir/xray_error.log（扩展探针会把尾部并入 vpn_diag 回传）；
// access 设为空字符串禁用访问日志防爆盘。解析/改写任何一步失败都
// 返回原 config，绝不阻断启动。
func rewriteLogConfig(cfg string, assetDir string) string {
	var root map[string]interface{}
	if err := json.Unmarshal([]byte(cfg), &root); err != nil {
		return cfg
	}
	logObj, ok := root["log"].(map[string]interface{})
	if !ok || logObj == nil {
		logObj = map[string]interface{}{}
	}
	level, _ := logObj["loglevel"].(string)
	if level == "" || level == "warning" || level == "error" {
		logObj["loglevel"] = "info"
	}
	if assetDir != "" {
		logObj["error"] = filepath.Join(assetDir, "xray_error.log")
	}
	logObj["access"] = ""
	root["log"] = logObj
	out, err := json.Marshal(root)
	if err != nil {
		return cfg
	}
	return string(out)
}

// XrayStart 启动 Xray 实例。
// configJSON: 完整 Xray JSON 配置（由 ArkTS 的 XrayConfig 生成）。
// assetDir:   资产目录（geoip.dat/geosite.dat 所在目录）；启动前
//
//	os.Setenv("XRAY_LOCATION_ASSET", assetDir)，xray-core 据此定位 dat 文件。
//
// 返回 0 成功，非 0 失败（细节见 XrayLastError）。
//
//export XrayStart
func XrayStart(configJSON *C.char, assetDir *C.char) C.int {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		_ = instance.Close()
		instance = nil
		runningConfig = ""
	}
	asset := C.GoString(assetDir)
	if asset != "" {
		_ = os.Setenv("XRAY_LOCATION_ASSET", asset)
		_ = os.Setenv("XRAY_LOCATION_CONFIG", asset)
		// 确保目录存在，避免内核写日志/缓存时报错
		_ = os.MkdirAll(filepath.Clean(asset), 0o755)
	}
	cfg := C.GoString(configJSON)
	if strings.TrimSpace(cfg) == "" {
		lastErr = "empty config"
		return 1
	}
	// v1.1.2：提升 loglevel 并把 error 日志落盘 xray_error.log（见 rewriteLogConfig）
	cfg = rewriteLogConfig(cfg, asset)
	// 以 JSON 格式加载配置（对应 core.LoadConfig("json", reader)）
	loaded, err := core.LoadConfig("json", bytes.NewReader([]byte(cfg)))
	if err != nil {
		lastErr = fmt.Sprintf("LoadConfig: %v", err)
		return 2
	}
	inst, err := core.New(loaded)
	if err != nil {
		lastErr = fmt.Sprintf("core.New: %v", err)
		return 3
	}
	if err := inst.Start(); err != nil {
		lastErr = fmt.Sprintf("StartInstance: %v", err)
		return 4
	}
	instance = inst
	runningConfig = cfg
	lastErr = ""
	return 0
}

// XrayStop 停止当前实例（对应 core.Instance.Close）。
//
//export XrayStop
func XrayStop() {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		_ = instance.Close()
		instance = nil
		runningConfig = ""
	}
}

// XrayVersion 返回 Xray-core 版本字符串（core.VersionStatement 拼接）。
//
//export XrayVersion
func XrayVersion() *C.char {
	return cString(strings.Join(core.VersionStatement(), " "))
}

// XrayLastError 返回最近一次错误。返回的 C 字符串由 Go 侧 C.CString 分配，
// NAPI 侧 makeString 拷贝后不释放会形成小量泄漏（v1 已知，量级可忽略）。
//
//export XrayLastError
func XrayLastError() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return cString(lastErr)
}

// httpInboundPort 从 Xray JSON 配置中解析 tag=http 的入站端口；无则用默认 10809。
func httpInboundPort(configJSON string) int {
	var root struct {
		Inbounds []struct {
			Tag  string `json:"tag"`
			Port int    `json:"port"`
		} `json:"inbounds"`
	}
	if err := json.Unmarshal([]byte(configJSON), &root); err != nil {
		return 10809
	}
	for _, in := range root.Inbounds {
		if in.Tag == "http" && in.Port > 0 {
			return in.Port
		}
	}
	return 10809
}

// measureViaHTTPProxy 经 127.0.0.1:httpPort 的 HTTP 代理 GET 目标 URL 并计时（毫秒）。
func measureViaHTTPProxy(httpPort int, target string, timeout time.Duration) int {
	proxyURL := &url.URL{Scheme: "http", Host: fmt.Sprintf("127.0.0.1:%d", httpPort)}
	client := &http.Client{
		Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL)},
		Timeout:   timeout,
	}
	start := time.Now()
	resp, err := client.Get(target)
	if err != nil {
		return -1
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	return int(time.Since(start) / time.Millisecond)
}

// XrayPing 真实延迟测试（对照 Android v2rayNG 的测速思路：经核心入站实测）。
//
// 路径二选一（按运行状态自动选择）：
//   - 已有实例在运行（扩展进程的节点探针走这条）：临时实例会与运行实例
//     抢占相同的入站端口必然冲突，故直接经运行实例的 HTTP 入站测速——
//     此时测得的是当前连接节点的延迟（传入 config 仅用于解析端口，端口与
//     运行配置不一致时以运行配置为准）。
//   - 无实例运行（UI 进程的节点测速走这条；UI 与扩展不在同一进程，UI 侧
//     永远无实例）：用传入 config 起一个临时实例，经其 HTTP 入站测速后
//     立即关闭。调用方必须传测速专用配置（XrayConfig.buildXrayTestConfig，
//     测试端口 18088/18089，与正式入站 10808/10809 分离）+ assetDir——
//     v1.2.1 前临时实例没设 XRAY_LOCATION_ASSET，规则模式的 geo 规则加载
//     失败导致测速恒 -1。
//
// assetDir 非空时在 LoadConfig 前 Setenv XRAY_LOCATION_ASSET/CONFIG、
// MkdirAll，并对 cfg 先过 rewriteLogConfig（失败原因同步落 xray_error.log
// 便于回传判读，v1.1.2 起正式启动路径同款处理）。
// 临时实例路径由 pingMu 整段串行化：并发 ping 会抢同一测试端口。
// 返回毫秒；失败返回 -1，原因写 lastErr（XrayLastError 回传 UI 显示）。
//
//export XrayPing
func XrayPing(configJSON *C.char, urlStr *C.char, timeoutMs C.int, assetDir *C.char) C.int {
	target := C.GoString(urlStr)
	if target == "" {
		target = "http://www.gstatic.com/generate_204"
	}
	timeout := time.Duration(timeoutMs) * time.Millisecond
	if timeout <= 0 {
		timeout = 5 * time.Second
	}
	cfg := C.GoString(configJSON)

	running, runCfg := snapshotInstance()
	if running != nil {
		port := httpInboundPort(runCfg)
		ms := measureViaHTTPProxy(port, target, timeout)
		if ms < 0 {
			setErrText(fmt.Sprintf("XrayPing 经运行实例 HTTP 入站 127.0.0.1:%d 测速失败: %s 无响应或超时", port, target))
		}
		return C.int(ms)
	}

	// 临时实例路径：整段串行（等锁期间正式实例可能已启动，取锁后复查一次）
	pingMu.Lock()
	defer pingMu.Unlock()
	if running2, runCfg2 := snapshotInstance(); running2 != nil {
		port := httpInboundPort(runCfg2)
		ms := measureViaHTTPProxy(port, target, timeout)
		if ms < 0 {
			setErrText(fmt.Sprintf("XrayPing 经运行实例 HTTP 入站 127.0.0.1:%d 测速失败: %s 无响应或超时", port, target))
		}
		return C.int(ms)
	}

	if strings.TrimSpace(cfg) == "" {
		setErrText("XrayPing: empty config")
		return -1
	}
	asset := C.GoString(assetDir)
	if asset != "" {
		_ = os.Setenv("XRAY_LOCATION_ASSET", asset)
		_ = os.Setenv("XRAY_LOCATION_CONFIG", asset)
		_ = os.MkdirAll(filepath.Clean(asset), 0o755)
		// 与 XrayStart 同款：loglevel 提升 + error 落盘 xray_error.log
		cfg = rewriteLogConfig(cfg, asset)
	}
	loaded, err := core.LoadConfig("json", bytes.NewReader([]byte(cfg)))
	if err != nil {
		setErrText(fmt.Sprintf("XrayPing LoadConfig: %v", err))
		return -1
	}
	inst, err := core.New(loaded)
	if err != nil {
		setErrText(fmt.Sprintf("XrayPing core.New: %v", err))
		return -1
	}
	if err := inst.Start(); err != nil {
		setErrText(fmt.Sprintf("XrayPing Start: %v", err))
		return -1
	}
	defer func() { _ = inst.Close() }()
	port := httpInboundPort(cfg)
	ms := measureViaHTTPProxy(port, target, timeout)
	if ms < 0 {
		setErrText(fmt.Sprintf("XrayPing 经临时实例 HTTP 入站 127.0.0.1:%d 测速失败: %s 无响应或超时（节点不可达或协议握手失败，细节看 xray_error.log）", port, target))
	}
	return C.int(ms)
}

// XrayTraffic 读取运行实例的 stats 计数器，返回 JSON：
//
//	{"up":累计上行字节,"down":累计下行字节,"upTotal":同 up,"downTotal":同 down,
//	 "directUp":直连上行,"directDown":直连下行}
//
// up/down 与 upTotal/downTotal 同为 proxy 出站累计字节（桥只给累计值，
// 速率由 UI 侧按采样差分计算）。计数器来自配置 policy.system 的
// statsOutboundUplink/Downlink（XrayConfig 生成端已开启），计数器名
// outbound>>>{tag}>>>traffic>>>{uplink|downlink}。
// 失败分支带 error 标记（v1.1.2，探针判读用）：无实例 {"error":"no-instance"}、
// GetFeature 为 nil {"error":"no-feature"}、类型断言失败 {"error":"bad-type"}；
// 正常路径仍返回计数 JSON。注意旧版"{}"无法区分失败原因，已弃用。
//
//export XrayTraffic
func XrayTraffic() *C.char {
	inst, _ := snapshotInstance()
	if inst == nil {
		return cString(`{"error":"no-instance"}`)
	}
	// xray v26：Instance.GetFeature 只返回单个值（旧版为 (value, error)）
	feat := inst.GetFeature(stats.ManagerType)
	if feat == nil {
		return cString(`{"error":"no-feature"}`)
	}
	mgr, ok := feat.(stats.Manager)
	if !ok || mgr == nil {
		return cString(`{"error":"bad-type"}`)
	}
	get := func(name string) int64 {
		// xray v26：GetCounter 只返回计数器本身，缺失时为 nil
		counter := mgr.GetCounter(name)
		if counter == nil {
			return 0
		}
		return counter.Value()
	}
	up := get("outbound>>>proxy>>>traffic>>>uplink")
	down := get("outbound>>>proxy>>>traffic>>>downlink")
	dUp := get("outbound>>>direct>>>traffic>>>uplink")
	dDown := get("outbound>>>direct>>>traffic>>>downlink")
	return cString(fmt.Sprintf(
		`{"up":%d,"down":%d,"upTotal":%d,"downTotal":%d,"directUp":%d,"directDown":%d}`,
		up, down, up, down, dUp, dDown))
}

// 释放辅助（供 NAPI 侧调用以释放 XrayVersion/XrayLastError/XrayTraffic 返回值）
//
//export XrayFreeCString
func XrayFreeCString(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}
