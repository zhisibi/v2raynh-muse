#!/usr/bin/env bash
# 构建 hev-socks5-tunnel 鸿蒙版：libhevtun.so（TUN -> SOCKS5 转发）
#
# 产物：entry/libs/arm64-v8a/libhevtun.so
# 上游：https://github.com/heiher/hev-socks5-tunnel（Android 侧 v2rayNG 用其
#       Android.mk / jni 构建为独立可执行/库；鸿蒙需改 NDK clang + 静态适配层）
#
# 本脚本先做：环境校验 + 克隆上游 + 编译骨架。
# 适配层约定（xray_napi.cpp 期望的 C ABI）：
#   int  HevTunnelStart(const char* configYaml, int tunFd); // 内部自建线程跑事件循环
#   void HevTunnelStop(void);
# 上游原生入口是阻塞式 hev_socks5_tunnel_main_from_str()（以其头文件为准），
# 因此正式移植时需在本目录的 hev_adapter.c 中：pthread_create 工作线程调
# 上游入口、Stop 时调上游的 quit/stop 接口。适配层未补齐前本脚本会明确报错退出，
# 不会产出假 .so；此时 App 仍可运行（startTun 返回 false，SOCKS 代理可用）。
#
# Android.mk 移植点（对照上游 Android 构建）：
#   1. LOCAL_MODULE/LOCAL_SRC_FILES 的源文件清单（src/*.c + 第三方 lwIP/yaml 源码）
#      直接沿用，改走 clang -c 逐文件编译后 ar/ld -shared；
#   2. Android 专用：去掉 -llog 链接与 JNI 入口（jni/ 目录不编），
#      日志改走 OHOS hilog 或 stderr；
#   3. 宏定义：保持上游 Android.mk 的 CFLAGS（如 -DHAVE_CONFIG_H 若有），
#      补 -D_GNU_SOURCE 与 OHOS 的 sysroot include 路径；
#   4. tun fd 由外部（NAPI 桥 dup 后）传入，不用上游 Android 的 VpnService fd 传递方式。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.ohos-core-build/hev"
OUT="$ROOT/entry/libs/arm64-v8a"
mkdir -p "$WORK" "$OUT"

OHOS_NDK_HOME="${OHOS_NDK_HOME:-}"
if [[ -z "$OHOS_NDK_HOME" ]]; then
  echo "请先设置 OHOS_NDK_HOME 指向 OpenHarmony SDK 的 native 目录"
  exit 1
fi
CLANG="$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang"
if [[ ! -x "$CLANG" ]]; then
  echo "找不到 aarch64 clang：$CLANG"
  exit 1
fi

SRC="$WORK/hev-socks5-tunnel"
if [[ ! -d "$SRC/.git" ]]; then
  echo "==> 克隆 hev-socks5-tunnel…"
  git clone --recursive https://github.com/heiher/hev-socks5-tunnel "$SRC"
fi

echo "上游结构："
ls "$SRC"
echo ""
echo "Android.mk 参考（移植源文件清单以此为准）："
find "$SRC" -name "Android.mk" -exec echo {} \; -exec cat {} \; || true

ADAPTER="$ROOT/scripts/hev_adapter.c"
if [[ ! -f "$ADAPTER" ]]; then
  cat <<'EOF'
!! 适配层 scripts/hev_adapter.c 尚未编写（真机迭代第一项）：
   需实现 HevTunnelStart/HevTunnelStop，内部以 pthread 调上游阻塞入口，
   并处理 tunFd 所有权与日志重定向。骨架步骤：
     1. 按上游 Android.mk 的 LOCAL_SRC_FILES 收集 src 与第三方源文件；
     2. $CLANG --target=aarch64-linux-ohos --sysroot=$OHOS_NDK_HOME/sysroot
        -fPIC -I<上游 include> -c 每个 .c 为 .o；
     3. $CLANG -shared -o entry/libs/arm64-v8a/libhevtun.so *.o hev_adapter.o；
     4. nm -D 验 HevTunnelStart/HevTunnelStop 符号。
   在此之前，TUN 转发不可用，App 的 SOCKS/HTTP 代理与核心功能不受影响。
EOF
  exit 2
fi

echo "==> 编译（适配层已存在，按其源文件清单执行）…"
# TODO（真机迭代）：按上游版本锁定源文件清单后在此补全编译命令。
echo "hev_adapter.c 存在但编译命令尚未锁定上游版本，未产出 .so。"
exit 2
