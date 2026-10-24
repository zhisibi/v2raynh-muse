// v2rayNG Harmony · VPN 拉起/停止入口（UI 层调用）
// 必须用 vpnExtension.startVpnExtensionAbility：用 startAbility 拉 ExtensionAbility
// 会报 "Incorrect ability type"（澜舟 1.0.0 真机实锤）。
import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';

const EXTENSION_ABILITY_NAME = 'V2RayVpnExtension';
export const PARAM_MODE = 'v2rayng_mode';

export class VpnService {
  private static uiContext: common.UIAbilityContext | undefined = undefined;

  static init(context: common.UIAbilityContext): void {
    VpnService.uiContext = context;
  }

  private static want(tunEnabled: boolean): Want {
    const context: common.UIAbilityContext | undefined = VpnService.uiContext;
    if (context === undefined) throw new Error('VpnService.init(context) 尚未调用');
    const params: Record<string, string> = {};
    params[PARAM_MODE] = tunEnabled ? 'tun' : 'proxy';
    const w: Want = {
      bundleName: context.abilityInfo.bundleName,
      abilityName: EXTENSION_ABILITY_NAME,
      parameters: params,
    };
    return w;
  }

  static async connect(tunEnabled: boolean): Promise<void> {
    await vpnExtension.startVpnExtensionAbility(VpnService.want(tunEnabled));
  }

  static disconnect(): void {
    try {
      vpnExtension.stopVpnExtensionAbility(VpnService.want(true)).catch(() => {
        // 扩展可能尚未运行，忽略
      });
    } catch (e) {
      // 忽略
    }
  }
}
