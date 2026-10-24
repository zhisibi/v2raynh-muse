// v2rayNG Harmony · 应用入口
import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VpnService } from '../service/VpnService';
import { SubscriptionManager } from '../model/SubscriptionManager';
import { LogStore, initLogFile } from '../model/LogStore';
import { SettingsStore } from '../model/SettingsStore';
import { ensureAssets } from '../model/AssetInstaller';

const TAG = 'V2RayApp';
const DOMAIN = 0xff01;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    (globalThis as Object as Record<string, Object>)['v2rayngAppContext'] = this.context;
    VpnService.init(this.context);
    initLogFile();
    // 预加载设置缓存（扩展进程读不到 UI 上下文时使用默认值，UI 进程保证已初始化）
    SettingsStore.get();
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
      }
    });
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
