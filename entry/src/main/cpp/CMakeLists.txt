# v2rayNG Harmony NAPI 桥：把 Go 核心（libxray.so）导出的 C ABI 转成 ArkTS 接口。
# 对应 Android: gomobile AAR (LibXray) 的 JNI 桥。鸿蒙无 JNI，用 NAPI 代替。
cmake_minimum_required(VERSION 3.5.0)
project(v2rayng_core)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

add_library(v2rayng_core SHARED xray_napi.cpp)

target_include_directories(v2rayng_core PRIVATE ${NATIVERENDER_ROOT_PATH})

# libxray.so / libhevtun.so 由 scripts/build-ohos-core.sh、build-hevtun.sh 交叉编译，
# 放入 entry/libs/arm64-v8a/；NAPI 侧只做 dlopen/dlsym，不做链接期依赖。
target_link_libraries(v2rayng_core PUBLIC libace_napi.z.so libhilog_ndk.z.so)
