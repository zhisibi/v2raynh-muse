#!/usr/bin/env bash
# 纯逻辑冒烟测试：把零鸿蒙依赖的 model/*.ets 复制为 .ts 后 tsc strict 编译，Node 运行
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TSC="$HOME/ohos-build/ohos-clt/command-line-tools/hvigor/hvigor/node_modules/typescript/bin/tsc"
if [[ ! -f "$TSC" ]]; then
  TSC="$(command -v tsc || true)"
fi
if [[ -z "${TSC:-}" || ! -f "$TSC" ]]; then
  echo "找不到 tsc"
  exit 1
fi
OUT=/tmp/v2rayng-smoke
rm -rf "$OUT"
mkdir -p "$OUT/src"
cp "$ROOT/entry/src/main/ets/model/UriParser.ets" "$OUT/src/UriParser.ts"
cp "$ROOT/entry/src/main/ets/model/XrayConfig.ets" "$OUT/src/XrayConfig.ts"
sed -e "s#'../entry/src/main/ets/model/UriParser'#'./UriParser'#g" \
    -e "s#'../entry/src/main/ets/model/XrayConfig'#'./XrayConfig'#g" \
    "$ROOT/tests/smoke-main.ts" > "$OUT/src/smoke-main.ts"
node "$TSC" --strict --target es2021 --module commonjs --moduleResolution node \
  --outDir "$OUT/build" "$OUT/src/smoke-main.ts"
node "$OUT/build/smoke-main.js"
