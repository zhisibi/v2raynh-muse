// v2rayNG Harmony · VPN 拉起/停止入口（UI 层调用）
// 必须用 vpnExtension.startVpnExtensionAbility：用 startAbility 拉 ExtensionAbility
// 会报 "Incorrect ability type"（澜舟 1.0.0 真机实锤）。
import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';

const EXTENSION_ABILITY_NAME = 'V2RayVpnExtension';
export const PARAM_MODE = 'v2rayng_mode';
export const PARAM_IPV6 = 'v2rayng_ipv6';

export class VpnService {
  private static uiContext: common.UIAbilityContext | undefined = undefined;

  static init(context: common.UIAbilityContext): void {
    VpnService.uiContext = context;
  }

  private static want(tunEnabled: boolean, ipv6Enabled: boolean): Want {
    const context: common.UIAbilityContext | undefined = VpnService.uiContext;
    if (context === undefined) throw new Error('VpnService.init(context) 尚未调用');
    const params: Record<string, string> = {};
    params[PARAM_MODE] = tunEnabled ? 'tun' : 'proxy';
    // v1.2.2：IPv6 设置经 want 参数进扩展（扩展进程读不到 UI 的 Preferences），
    // 扩展据此决定 VpnConfig 双栈/仅 v4 与 hev yaml 是否带 ipv6 行。
    params[PARAM_IPV6] = ipv6Enabled ? '1' : '0';
    const w: Want = {
      bundleName: context.abilityInfo.bundleName,
      abilityName: EXTENSION_ABILITY_NAME,
      parameters: params,
    };
    return w;
  }

  static async connect(tunEnabled: boolean, ipv6Enabled: boolean): Promise<void> {
    await vpnExtension.startVpnExtensionAbility(VpnService.want(tunEnabled, ipv6Enabled));
  }

  static disconnect(): void {
    try {
      // 停止不依赖 mode/ipv6 参数，传默认值即可（want 仅用于定位扩展）
      vpnExtension.stopVpnExtensionAbility(VpnService.want(true, true)).catch(() => {
        // 扩展可能尚未运行，忽略
      });
    } catch (e) {
      // 忽略
    }
  }
}
