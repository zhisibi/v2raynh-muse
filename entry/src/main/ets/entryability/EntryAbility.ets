// v2rayNG Harmony · 应用入口
import { UIAbility, AbilityConstant, Configuration, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VpnService } from '../service/VpnService';
import { ConnectManager } from '../service/ConnectManager';
import { ServerStore } from '../model/ServerStore';
import { SubscriptionManager } from '../model/SubscriptionManager';
import { LogStore, initLogFile } from '../model/LogStore';
import { SettingsStore } from '../model/SettingsStore';
import { ensureAssets } from '../model/AssetInstaller';
import { applyPalette, resolveDark } from '../components/Ui';

const TAG = 'V2RayApp';
const DOMAIN = 0xff01;

export default class EntryAbility extends UIAbility {
  private autoConnectTried: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    (globalThis as Object as Record<string, Object>)['v2rayngAppContext'] = this.context;
    VpnService.init(this.context);
    initLogFile();
    // 预加载设置缓存（扩展进程读不到 UI 上下文时使用默认值，UI 进程保证已初始化）
    SettingsStore.get();
    // 界面主题：按设置应用颜色模式（跟随系统/浅色/深色）
    SettingsStore.applyColorMode(this.context);
    // 自绘调色板同步（v1.2.2）：Pal 是硬编码常量，setColorMode 影响不到，
    // 按 themeMode 与系统当前深浅换 Pal 值，主题才真的变色。
    const sysDark: boolean =
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    applyPalette(resolveDark(SettingsStore.get().themeMode, sysDark));
    // 释放 geoip/geosite 到 filesDir/xray_assets（Xray 规则模式依赖，幂等）
    ensureAssets().catch(() => {
      // 失败已记日志，连接前会再试
    });
    LogStore.push('应用', 'v2rayNG 启动');
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        LogStore.push('应用', 'loadContent 失败: ' + JSON.stringify(err));
        return;
      }
      // 启动自动连接（设置开启且有选中节点时；失败静默记日志）
      if (SettingsStore.get().autoConnect && !this.autoConnectTried) {
        this.autoConnectTried = true;
        const sel = ServerStore.getSelected();
        if (sel !== undefined && ConnectManager.status() !== 'running') {
          ConnectManager.connect().then((cerr: string) => {
            if (cerr.length > 0) {
              LogStore.push('应用', '自动连接未成功：' + cerr);
            }
          }).catch((e: Error) => {
            LogStore.push('应用', '自动连接异常：' + String(e));
          });
        }
      }
    });
  }

  /** 系统配置变化（v1.2.2）：主题为「跟随系统」时，系统深浅切换须重应用调色板 */
  onConfigurationUpdate(newConfig: Configuration): void {
    if (SettingsStore.get().themeMode === 'system') {
      applyPalette(newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    }
  }

  onForeground(): void {
    SubscriptionManager.checkDue().catch(() => {
      // 静默
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onDestroy');
  }
}
