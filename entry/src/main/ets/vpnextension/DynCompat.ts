// 动态兼容调用：protectProcessNet 在新版本 HarmonyOS 运行时存在，但本地
// API 18 SDK 的 .d.ts 未声明；ArkTS 严格模式禁止动态成员访问，故用普通 .ts。
export function protectProcessNetDyn(conn: Object): void {
  const c = conn as any;
  if (c && typeof c.protectProcessNet === 'function') {
    c.protectProcessNet();
  }
}

// VpnConfig.allowedApplications 同样不在 API 18 的 .d.ts 类型里（只有
// blockedApplications）；运行时若支持则动态写入 allow 名单，返回是否写成功。
export function setAllowedApplicationsDyn(cfg: Object, bundles: string[]): boolean {
  const c = cfg as any;
  try {
    c.allowedApplications = bundles.slice();
    return Array.isArray(c.allowedApplications) &&
      c.allowedApplications.length === bundles.length;
  } catch (e) {
    return false;
  }
}
