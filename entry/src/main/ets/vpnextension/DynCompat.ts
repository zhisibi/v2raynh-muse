// 动态兼容调用：protectProcessNet 在新版本 HarmonyOS 运行时存在，但本地
// API 18 SDK 的 .d.ts 未声明；ArkTS 严格模式禁止动态成员访问，故用普通 .ts。
export function protectProcessNetDyn(conn: Object): void {
  const c = conn as any;
  if (c && typeof c.protectProcessNet === 'function') {
    c.protectProcessNet();
  }
}
