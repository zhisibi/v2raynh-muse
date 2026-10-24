#!/usr/bin/env bash
# 构建 hev-socks5-tunnel 鸿蒙版：libhevtun.so（TUN -> SOCKS5 转发）
#
# 产物：entry/libs/arm64-v8a/libhevtun.so（导出 HevTunnelStart/HevTunnelStop）
# 上游：https://github.com/heiher/hev-socks5-tunnel（--recursive 克隆到
#       .ohos-core-build/hev-src；含子模块 yaml / lwip / hev-task-system）
#
# 与上游 Android.mk 的对应关系（共享库目标 hev-socks5-tunnel）：
#   - 源文件清单：各组件 build.mk 的 rwildcard(src/, *.c *.S) 递归收集；
#   - 宏：-DENABLE_LIBRARY -DFD_SET_DEFINED -DSOCKLEN_T_DEFINED（同 Android.mk）；
#     yaml 的 YAML_VERSION_* 与 hev-task-system 的 CONFIG_* 按各自 configs.mk 展开；
#     ENABLE_MEMALLOC_SLICE 按 hev 顶层 Android.mk 意图关闭（不定义），
#     ENABLE_IO_SPLICE_SYSCALL 不定义（OHOS musl 的 splice 可用性未验证，
#     代码走 read/write 回退路径）；
#   - 去掉 Android 专用：不编 jni/、不链 -llog；日志走 stderr；
#   - COMMIT_ID 用上游 git short id（VERSION_CFLAGS 同上游 build.mk）。
# 适配层：core/hev/hev_adapter.c —— pthread 包上游阻塞入口
#   hev_socks5_tunnel_main_from_str / hev_socks5_tunnel_quit，
#   导出 NAPI 桥约定的 HevTunnelStart/HevTunnelStop。
#
# 用法：
#   OHOS_NDK_HOME=~/ohos-build/ohos-clt/command-line-tools/sdk/default/openharmony/native \
#     ./scripts/build-hevtun.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.ohos-core-build"
OUT="$ROOT/entry/libs/arm64-v8a"
mkdir -p "$WORK" "$OUT"

OHOS_NDK_HOME="${OHOS_NDK_HOME:-$HOME/ohos-build/ohos-clt/command-line-tools/sdk/default/openharmony/native}"
CLANG="$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang"
if [[ ! -x "$CLANG" ]]; then
  echo "找不到 aarch64 clang：$CLANG（请设置 OHOS_NDK_HOME）"
  exit 1
fi

SRC="$WORK/hev-src"
if [[ ! -d "$SRC/.git" ]]; then
  echo "==> 克隆 hev-socks5-tunnel（--recursive）…"
  git clone --recursive https://github.com/heiher/hev-socks5-tunnel "$SRC"
fi

ADAPTER="$ROOT/core/hev/hev_adapter.c"
if [[ ! -f "$ADAPTER" ]]; then
  echo "!! 适配层缺失：$ADAPTER"
  exit 2
fi

REV_ID="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)"
OBJ="$WORK/hev-obj"
rm -rf "$OBJ"
mkdir -p "$OBJ"

INCLUDES=(
  -I"$SRC/src"
  -I"$SRC/src/misc"
  -I"$SRC/src/core/include"
  -I"$SRC/third-part/yaml/include"
  -I"$SRC/third-part/yaml/src"
  -I"$SRC/third-part/lwip/src/include"
  -I"$SRC/third-part/lwip/src/ports/include"
  -I"$SRC/third-part/hev-task-system/include"
  -I"$SRC/third-part/hev-task-system/src"
)
BASE_FLAGS=(
  --target=aarch64-linux-ohos
  --sysroot="$OHOS_NDK_HOME/sysroot"
  -fPIC -O2 -fno-stack-clash-protection
  -D_GNU_SOURCE
  -DFD_SET_DEFINED -DSOCKLEN_T_DEFINED -DENABLE_LIBRARY
  -DCOMMIT_ID="\"$REV_ID\""
  -DYAML_VERSION_MAJOR=0 -DYAML_VERSION_MINOR=2 -DYAML_VERSION_PATCH=5
  -DYAML_VERSION_STRING="\"0.2.5\""
  -DENABLE_STACK_OVERFLOW_DETECTION
  -DCONFIG_STACK_BACKEND=STACK_MMAP
  -DCONFIG_STACK_OVERFLOW_DETECTION=1
  -DCONFIG_MEMALLOC_SLICE_ALIGN=16
  -DCONFIG_MEMALLOC_SLICE_MAX_SIZE=4096
  -DCONFIG_MEMALLOC_SLICE_MAX_COUNT=1000
  -DCONFIG_SCHED_CLOCK=CLOCK_NONE
  -w
)

echo "==> 收集源文件（同上游 rwildcard，按组件分组）…"
# 必须按组件建静态库再链接（同 Android ndk-build 的 LOCAL_STATIC_LIBRARIES
# 语义）：hev 本体与 hev-task-system 各自带了一份 hev-list/hev-rbtree，
# 直接全 .o 链接会重复符号；归档后链接器只按需拉取成员即不冲突。
AR="$OHOS_NDK_HOME/llvm/bin/llvm-ar"
[[ -x "$AR" ]] || AR=ar

compile_component() {
  # $1=组件名 $2=源文件根目录 $3...=额外源文件
  local name="$1" dir="$2"
  shift 2
  local objs=()
  local i=0
  local f o
  while IFS= read -r f; do
    i=$((i + 1))
    o="$OBJ/${name}_$i.o"
    "$CLANG" "${BASE_FLAGS[@]}" "${INCLUDES[@]}" -c "$f" -o "$o"
    objs+=("$o")
  done < <(find "$dir" \( -name '*.c' -o -name '*.S' \) | sort)
  for f in "$@"; do
    i=$((i + 1))
    o="$OBJ/${name}_$i.o"
    "$CLANG" "${BASE_FLAGS[@]}" "${INCLUDES[@]}" -c "$f" -o "$o"
    objs+=("$o")
  done
  "$AR" rcs "$OBJ/lib$name.a" "${objs[@]}"
  echo "    $name: ${#objs[@]} 个源文件"
}

compile_component hevmain "$SRC/src" "$ADAPTER"
compile_component yaml "$SRC/third-part/yaml/src"
compile_component lwip "$SRC/third-part/lwip/src"
compile_component task "$SRC/third-part/hev-task-system/src"

echo "==> 链接 libhevtun.so…"
"$CLANG" --target=aarch64-linux-ohos --sysroot="$OHOS_NDK_HOME/sysroot" \
  -shared -o "$OUT/libhevtun.so" \
  -Wl,--whole-archive "$OBJ/libhevmain.a" -Wl,--no-whole-archive \
  "$OBJ/libyaml.a" "$OBJ/liblwip.a" "$OBJ/libtask.a" \
  -lpthread -lm
ls -lh "$OUT/libhevtun.so"

echo "==> 验符号…"
NM="$OHOS_NDK_HOME/llvm/bin/llvm-nm"
[[ -x "$NM" ]] || NM=nm
"$NM" -D "$OUT/libhevtun.so" | grep -E "HevTunnel(Start|Stop)" || {
  echo "!! 缺少 HevTunnelStart/HevTunnelStop 导出符号"
  exit 1
}
echo "构建完成：$OUT/libhevtun.so"
