// v2rayNG Harmony · 应用设置（Preferences 持久化）
import { preferences } from '@kit.ArkData';
import { ConfigurationConstant, Context } from '@kit.AbilityKit';
import { AppSettings, CustomRules, defaultCustomRules, defaultSettings, RoutingMode } from './XrayConfig';

const PREF_NAME = 'v2rayng_settings';

let pref: preferences.Preferences | undefined = undefined;
let cache: AppSettings | undefined = undefined;

function getPref(): preferences.Preferences | undefined {
  const ctx: Object | undefined = (globalThis as Object as Record<string, Object>)['v2rayngAppContext'];
  if (ctx === undefined) return undefined;
  try {
    if (pref === undefined) {
      pref = preferences.getPreferencesSync(ctx as Context, { name: PREF_NAME });
    }
    return pref;
  } catch (e) {
    return undefined;
  }
}

function copyCustomRules(r: CustomRules | undefined): CustomRules {
  const d: CustomRules = defaultCustomRules();
  if (r === undefined) return d;
  const out: CustomRules = {
    directDomain: typeof r.directDomain === 'string' ? r.directDomain : '',
    proxyDomain: typeof r.proxyDomain === 'string' ? r.proxyDomain : '',
    blockDomain: typeof r.blockDomain === 'string' ? r.blockDomain : '',
    directIp: typeof r.directIp === 'string' ? r.directIp : '',
    proxyIp: typeof r.proxyIp === 'string' ? r.proxyIp : '',
  };
  return out;
}

function copySettings(s: AppSettings): AppSettings {
  const mode: RoutingMode =
    s.routingMode === 'global' || s.routingMode === 'direct' ? s.routingMode : 'rule';
  const out: AppSettings = {
    socksPort: s.socksPort,
    httpPort: s.httpPort,
    routingMode: mode,
    enableUdp: s.enableUdp,
    sniffingEnabled: s.sniffingEnabled,
    ipv6Enabled: s.ipv6Enabled,
    localDns: s.localDns,
    remoteDns: s.remoteDns,
    subUpdateHours: s.subUpdateHours,
    tunEnabled: s.tunEnabled,
    logLevel: s.logLevel,
    perAppMode: s.perAppMode === 'block' || s.perAppMode === 'allow' ? s.perAppMode : 'off',
    perAppList: s.perAppList,
    customRules: copyCustomRules(s.customRules),
    themeMode: s.themeMode === 'light' || s.themeMode === 'dark' ? s.themeMode : 'system',
    autoConnect: s.autoConnect === true,
  };
  return out;
}

export class SettingsStore {
  static get(): AppSettings {
    if (cache !== undefined) return copySettings(cache);
    const s: AppSettings = defaultSettings();
    const p: preferences.Preferences | undefined = getPref();
    if (p !== undefined) {
      try {
        s.socksPort = p.getSync('socksPort', 10808) as number;
        s.httpPort = p.getSync('httpPort', 10809) as number;
        const m: string = p.getSync('routingMode', 'rule') as string;
        s.routingMode = (m === 'global' || m === 'direct') ? m : 'rule';
        s.enableUdp = p.getSync('enableUdp', true) as boolean;
        s.sniffingEnabled = p.getSync('sniffingEnabled', true) as boolean;
        s.ipv6Enabled = p.getSync('ipv6Enabled', true) as boolean;
        s.localDns = p.getSync('localDns', '223.5.5.5') as string;
        s.remoteDns = p.getSync('remoteDns', '1.1.1.1') as string;
        s.subUpdateHours = p.getSync('subUpdateHours', 24) as number;
        s.tunEnabled = p.getSync('tunEnabled', true) as boolean;
        s.logLevel = p.getSync('logLevel', 'warning') as string;
        const pm: string = p.getSync('perAppMode', 'off') as string;
        s.perAppMode = (pm === 'block' || pm === 'allow') ? pm : 'off';
        s.perAppList = p.getSync('perAppList', '') as string;
        s.customRules.directDomain = p.getSync('crDirectDomain', '') as string;
        s.customRules.proxyDomain = p.getSync('crProxyDomain', '') as string;
        s.customRules.blockDomain = p.getSync('crBlockDomain', '') as string;
        s.customRules.directIp = p.getSync('crDirectIp', '') as string;
        s.customRules.proxyIp = p.getSync('crProxyIp', '') as string;
        const tm: string = p.getSync('themeMode', 'system') as string;
        s.themeMode = (tm === 'light' || tm === 'dark') ? tm : 'system';
        s.autoConnect = p.getSync('autoConnect', false) as boolean;
      } catch (e) {
        // 使用默认值
      }
    }
    cache = copySettings(s);
    return copySettings(s);
  }

  static save(s: AppSettings): void {
    cache = copySettings(s);
    const p: preferences.Preferences | undefined = getPref();
    if (p === undefined) return;
    try {
      p.putSync('socksPort', s.socksPort);
      p.putSync('httpPort', s.httpPort);
      p.putSync('routingMode', s.routingMode);
      p.putSync('enableUdp', s.enableUdp);
      p.putSync('sniffingEnabled', s.sniffingEnabled);
      p.putSync('ipv6Enabled', s.ipv6Enabled);
      p.putSync('localDns', s.localDns);
      p.putSync('remoteDns', s.remoteDns);
      p.putSync('subUpdateHours', s.subUpdateHours);
      p.putSync('tunEnabled', s.tunEnabled);
      p.putSync('logLevel', s.logLevel);
      p.putSync('perAppMode', s.perAppMode);
      p.putSync('perAppList', s.perAppList);
      const cr: CustomRules = copyCustomRules(s.customRules);
      p.putSync('crDirectDomain', cr.directDomain);
      p.putSync('crProxyDomain', cr.proxyDomain);
      p.putSync('crBlockDomain', cr.blockDomain);
      p.putSync('crDirectIp', cr.directIp);
      p.putSync('crProxyIp', cr.proxyIp);
      p.putSync('themeMode', s.themeMode);
      p.putSync('autoConnect', s.autoConnect);
      p.flush();
    } catch (e) {
      // 忽略持久化失败
    }
  }

  /** 按 themeMode 应用颜色模式到整个应用（ApplicationContext.setColorMode） */
  static applyColorMode(ctx: Context): void {
    try {
      const mode: string = SettingsStore.get().themeMode;
      const cm: ConfigurationConstant.ColorMode =
        mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
          (mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
            ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      ctx.getApplicationContext().setColorMode(cm);
    } catch (e) {
      // SDK 不支持时忽略（重启后由系统主题决定）
    }
  }
}
