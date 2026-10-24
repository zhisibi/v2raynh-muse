#!/usr/bin/env bash
# 构建 v2rayNG 鸿蒙版 Go 核心：libxray.so（c-shared）
#
# 产物：entry/libs/arm64-v8a/libxray.so
# 前置：
#   1. OpenHarmony SDK native 工具链（OHOS_NDK_HOME 指向 .../native）
#   2. 可访问 gitcode/github（OpenHarmony Go fork、Xray-core 依赖）
#   3. 约 3GB 磁盘，首次构建 Go 工具链数分钟，Xray 编译数分钟到数十分钟
#
# 用法：
#   OHOS_NDK_HOME=/path/to/sdk/default/openharmony/native ./scripts/build-ohos-core.sh
#
# 仿 ~/workspace/mihomo-lite-harmony/scripts/build-ohos-core.sh 的已验证流程，
# 差异：内核换为 XTLS/Xray-core，桥在 core/xray-bridge（本仓库），
# 导出符号 XrayStart/XrayStop/XrayVersion/XrayLastError/XrayPing。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.ohos-core-build"
OUT="$ROOT/entry/libs/arm64-v8a"
mkdir -p "$WORK" "$OUT"

OHOS_NDK_HOME="${OHOS_NDK_HOME:-}"
if [[ -z "$OHOS_NDK_HOME" ]]; then
  echo "请先设置 OHOS_NDK_HOME 指向 OpenHarmony SDK 的 native 目录"
  echo "例：export OHOS_NDK_HOME=~/ohos-build/ohos-clt/command-line-tools/sdk/default/openharmony/native"
  exit 1
fi
if [[ ! -x "$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang" ]]; then
  echo "OHOS_NDK_HOME 下找不到 aarch64 clang：$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang"
  exit 1
fi

# ---- 1. OpenHarmony Go fork（release-branch.go1.24，镜像兜底） ----
GO_FORK_URL="${GO_FORK_URL:-https://gitcode.com/openharmony-sig/ohos_golang_go.git}"
GO_FORK_BRANCH="${GO_FORK_BRANCH:-release-branch.go1.24}"
GO_FORK_MIRROR_URL="https://github.com/sysit/ohos-go.git"
GO_FORK_MIRROR_BRANCH="release-branch.go1.26"
if [[ ! -x "$WORK/go-ohos/bin/go" ]]; then
  echo "==> 获取 OpenHarmony Go fork…"
  if [[ -d "$WORK/go-src/.git" ]]; then
    echo "    复用已有 $WORK/go-src"
  elif ! timeout 60 git clone --depth 1 -b "$GO_FORK_BRANCH" "$GO_FORK_URL" "$WORK/go-src" 2>/dev/null; then
    echo "    主源不可达，改用 GitHub 镜像 $GO_FORK_MIRROR_URL ($GO_FORK_MIRROR_BRANCH)"
    rm -rf "$WORK/go-src"
    git clone --depth 1 -b "$GO_FORK_MIRROR_BRANCH" "$GO_FORK_MIRROR_URL" "$WORK/go-src"
  fi
  echo "==> 编译 Go 工具链（约需数分钟）…"
  if [[ -z "${GOROOT_BOOTSTRAP:-}" ]]; then
    if command -v go >/dev/null 2>&1; then
      export GOROOT_BOOTSTRAP="$(go env GOROOT)"
    else
      echo "    下载宿主 Go（bootstrap 用）…"
      mkdir -p "$WORK/host-go"
      if [[ ! -x "$WORK/host-go/go/bin/go" ]]; then
        curl -sL -o "$WORK/go-host.tar.gz" https://go.dev/dl/go1.24.6.linux-amd64.tar.gz
        tar -xzf "$WORK/go-host.tar.gz" -C "$WORK/host-go"
      fi
      export GOROOT_BOOTSTRAP="$WORK/host-go/go"
    fi
  fi
  export GOTOOLCHAIN=local
  (cd "$WORK/go-src/src" && bash ./make.bash)
  mkdir -p "$WORK/go-ohos"
  cp -r "$WORK/go-src"/* "$WORK/go-ohos"/
fi
export GOROOT="$WORK/go-ohos"
export PATH="$GOROOT/bin:$PATH"
go version

# ---- 2. 准备桥接模块（本仓库 core/xray-bridge，拉取 xray-core 依赖） ----
BRIDGE="$WORK/xray-bridge"
rm -rf "$BRIDGE"
cp -r "$ROOT/core/xray-bridge" "$BRIDGE"
echo "==> 拉取 Xray-core 依赖（版本以 go get 解析的最新稳定版为准）…"
(cd "$BRIDGE" && GOTOOLCHAIN=local go mod tidy)

# ---- 3. 交叉编译 c-shared ----
echo "==> 编译 libxray.so（GOOS=openharmony, arm64）…"
(cd "$BRIDGE" && \
  GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1 \
  CC="$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang" \
  go build -buildmode=c-shared -o "$OUT/libxray.so" .)

echo "==> 完成：$OUT/libxray.so"
ls -lh "$OUT/libxray.so"

# ---- 4. 验符号 ----
echo "导出符号检查："
nm -D "$OUT/libxray.so" | grep -E "Xray(Start|Stop|Version|LastError|Ping)" || {
  echo "!! 缺少 Xray* 导出符号，构建异常"
  exit 1
}

# ---- 5. TLS 重定位检查（TPREL 会导致鸿蒙 dlopen 失败，只允许 TLSDESC） ----
echo "TLS 重定位检查："
READELF="$OHOS_NDK_HOME/llvm/bin/llvm-readelf"
if [[ -x "$READELF" ]]; then
  if "$READELF" -r "$OUT/libxray.so" | grep -q "TPREL"; then
    echo "!! 发现 TPREL TLS 重定位，鸿蒙 dlopen 会失败；需检查 Go fork 版本/补丁"
    exit 1
  fi
  echo "    未发现 TPREL，通过"
else
  echo "    （无 llvm-readelf，跳过；真机加载失败时优先怀疑 TLS 重定位）"
fi
echo "构建完成。重新运行 hvigorw assembleHap 打包 HAP（大小应显著增大）。"
