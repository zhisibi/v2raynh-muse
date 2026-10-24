// v2rayNG Harmony · 应用设置（Preferences 持久化）
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { AppSettings, defaultSettings, RoutingMode } from './XrayConfig';

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
      p.flush();
    } catch (e) {
      // 忽略持久化失败
    }
  }
}
