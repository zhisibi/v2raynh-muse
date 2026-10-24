// v2rayNG Harmony · Xray 核心 Go 桥（c-shared）
//
// 对应 Android：AndroidLibXrayLite（gomobile bind 出 AAR，Kotlin 调 LibXray）。
// 鸿蒙路线：OpenHarmony Go fork 编 -buildmode=c-shared 出 libxray.so，
// 导出下列 C ABI 给 entry/src/main/cpp/xray_napi.cpp 经 dlopen 调用。
//
// 依赖版本：github.com/xtls/xray-core 以构建时 `go get` 到的最新稳定版为准
// （本文撰写时 v1.8.x 系列之后已有更新版本；go.mod 中版本仅为起点，
// 构建脚本会执行 go mod tidy 并以实际解析版本为准）。
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"unsafe"

	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all" // 注册全部协议/传输/路由实现
)

var (
	mu       sync.Mutex
	instance *core.Instance
	lastErr  string
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

func cString(s string) *C.char {
	return C.CString(s)
}

// XrayStart 启动 Xray 实例。
// configJSON: 完整 Xray JSON 配置（由 ArkTS 的 XrayConfig 生成）。
// assetDir:   资产目录（geoip.dat/geosite.dat 所在目录）；会设置为
//
//	XRAY_LOCATION_ASSET 环境对应的查找目录——xray-core 通过
//	core.GetAssetLocation / 环境变量定位 dat 文件，本桥在启动前
//	os.Setenv("XRAY_LOCATION_ASSET", assetDir)。
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
	}
}

// XrayVersion 返回 Xray-core 版本字符串（如 "Xray 1.8.x" 风格，具体以 core.Version 为准）。
//
//export XrayVersion
func XrayVersion() *C.char {
	return cString(core.VersionStatement())
}

// XrayLastError 返回最近一次错误（NAPI 侧负责在读取后……注意：返回的 C 字符串
// 由 Go 侧 C.CString 分配，调用方应 copy 后 C.free；本桥为简化约定：
// 每次调用都会生成新字符串，NAPI 侧 makeString 拷贝后不释放会形成小量泄漏，
// 真机迭代时改为固定缓冲区或由 NAPI 侧释放——TODO）。
//
//export XrayLastError
func XrayLastError() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return cString(lastErr)
}

// XrayPing 占位：v1 未实现真实延迟测试（需用临时实例 + HTTP 拨号测量，
// 与 Android 的 LibXray ping 思路一致但工作量独立），返回 -1 表示不可用；
// ArkTS 侧 testDelay 收到 -1 后回退 TCP 直连测速。
//
//export XrayPing
func XrayPing(configJSON *C.char, url *C.char, timeoutMs C.int) C.int {
	_ = configJSON
	_ = url
	_ = timeoutMs
	return -1
}

// XrayTraffic 可选导出：累计上下行字节 JSON。
// v1 占位返回 "{}"——core 的 stats 需经 policy/system 配置 + StatsManager
// 查询 outbound tag 计数器，真机迭代时补齐（配置生成器已开启 statsOutbound*）。
//
//export XrayTraffic
func XrayTraffic() *C.char {
	return cString("{}")
}

// 释放辅助（供未来 NAPI 侧调用以释放 XrayVersion/XrayLastError 返回值）
//
//export XrayFreeCString
func XrayFreeCString(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}
