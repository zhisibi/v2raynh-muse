// v2rayNG Harmony · 订阅管理（对照 Android handler/SubscriptionUpdater.kt + MmkvManager 订阅部分）
// 拉取：@kit.NetworkKit http，UA=v2rayNG/Harmony；内容：base64 或明文多行 URI；
// 响应头 subscription-userinfo 解析流量/到期（尽力而为）。
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { ProfileItem, parseSubscriptionText } from './UriParser';
import { ServerStore } from './ServerStore';
import { LogStore } from './LogStore';
import { SettingsStore } from './SettingsStore';

export interface Subscription {
  id: string;
  name: string;
  url: string;
  enabled: boolean;
  lastUpdate: number;
  nodeCount: number;
  expireAt: number;
  upload: number;
  download: number;
  total: number;
}

const PREF_NAME = 'v2rayng_subs';
const KEY = 'subs';

let pref: preferences.Preferences | undefined = undefined;
let cache: Subscription[] | undefined = undefined;

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

function loadAll(): Subscription[] {
  if (cache !== undefined) return cache;
  cache = [];
  const p: preferences.Preferences | undefined = getPref();
  if (p !== undefined) {
    try {
      cache = JSON.parse(p.getSync(KEY, '[]') as string) as Subscription[];
    } catch (e) {
      cache = [];
    }
  }
  return cache;
}

function persist(): void {
  const p: preferences.Preferences | undefined = getPref();
  if (p === undefined || cache === undefined) return;
  try {
    p.putSync(KEY, JSON.stringify(cache));
    p.flush();
  } catch (e) {
    // 忽略
  }
}

function genId(): string {
  return 's' + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
}

/** 解析 subscription-userinfo: upload=..; download=..; total=..; expire=.. */
export function parseUserInfo(header: string, sub: Subscription): void {
  const parts: string[] = header.split(';');
  for (let i = 0; i < parts.length; i++) {
    const kv: string[] = parts[i].split('=');
    if (kv.length !== 2) continue;
    const k: string = kv[0].trim();
    const v: number = Number(kv[1].trim());
    if (isNaN(v)) continue;
    if (k === 'upload') sub.upload = v;
    if (k === 'download') sub.download = v;
    if (k === 'total') sub.total = v;
    if (k === 'expire') sub.expireAt = v * 1000;
  }
}

export class SubscriptionManager {
  static getAll(): Subscription[] {
    return loadAll().slice();
  }

  static add(name: string, url: string): Subscription {
    const subs: Subscription[] = loadAll();
    const sub: Subscription = {
      id: genId(),
      name: name.length > 0 ? name : url,
      url: url,
      enabled: true,
      lastUpdate: 0,
      nodeCount: 0,
      expireAt: 0,
      upload: 0,
      download: 0,
      total: 0,
    };
    subs.push(sub);
    cache = subs;
    persist();
    return sub;
  }

  static update(id: string, name: string, url: string, enabled: boolean): void {
    const subs: Subscription[] = loadAll();
    for (let i = 0; i < subs.length; i++) {
      if (subs[i].id === id) {
        subs[i].name = name;
        subs[i].url = url;
        subs[i].enabled = enabled;
      }
    }
    persist();
  }

  static remove(id: string): void {
    const subs: Subscription[] = loadAll();
    cache = subs.filter((s: Subscription) => s.id !== id);
    ServerStore.clearBySubscription(id);
    persist();
  }

  /** 备份恢复：整体替换订阅列表（入参为 JSON 解析出的普通对象数组，只做字段消毒） */
  static restoreAll(rawSubs: Object[]): number {
    const out: Subscription[] = [];
    for (let i = 0; i < rawSubs.length; i++) {
      const o: Record<string, Object> = rawSubs[i] as Object as Record<string, Object>;
      const url: string = String(o['url'] ?? '');
      if (url.length === 0) continue;
      const num = (v: Object | undefined, dflt: number): number => {
        const n: number = Number(v ?? dflt);
        return isNaN(n) ? dflt : n;
      };
      const sub: Subscription = {
        id: String(o['id'] ?? genId()),
        name: String(o['name'] ?? url),
        url: url,
        enabled: Boolean(o['enabled'] ?? true),
        lastUpdate: num(o['lastUpdate'], 0),
        nodeCount: num(o['nodeCount'], 0),
        expireAt: num(o['expireAt'], 0),
        upload: num(o['upload'], 0),
        download: num(o['download'], 0),
        total: num(o['total'], 0),
      };
      out.push(sub);
    }
    cache = out;
    persist();
    return out.length;
  }

  /** 拉取并刷新单个订阅；返回新增节点数，失败抛错 */
  static async refresh(id: string): Promise<number> {
    const subs: Subscription[] = loadAll();
    let sub: Subscription | undefined = undefined;
    for (let i = 0; i < subs.length; i++) {
      if (subs[i].id === id) sub = subs[i];
    }
    if (sub === undefined) throw new Error('订阅不存在');
    LogStore.push('订阅', '更新订阅 ' + sub.name);
    const request: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await request.request(sub.url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': 'v2rayNG/Harmony' },
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      if (resp.responseCode !== 200) {
        throw new Error('HTTP ' + resp.responseCode);
      }
      const headers: Record<string, string> = resp.header as Object as Record<string, string>;
      const info: string = String(headers['subscription-userinfo'] ?? headers['Subscription-Userinfo'] ?? '');
      if (info.length > 0) parseUserInfo(info, sub);
      const body: string = String(resp.result ?? '');
      const profiles: ProfileItem[] = parseSubscriptionText(body);
      if (profiles.length === 0) {
        throw new Error('订阅内容未解析出节点（可能不是 v2rayNG 格式）');
      }
      for (let i = 0; i < profiles.length; i++) {
        profiles[i].subscriptionId = sub.id;
      }
      ServerStore.clearBySubscription(sub.id);
      ServerStore.addMany(profiles);
      sub.lastUpdate = Date.now();
      sub.nodeCount = profiles.length;
      persist();
      LogStore.push('订阅', sub.name + ' 更新完成：' + profiles.length + ' 个节点');
      return profiles.length;
    } finally {
      request.destroy();
    }
  }

  static async refreshAll(): Promise<void> {
    const subs: Subscription[] = loadAll();
    for (let i = 0; i < subs.length; i++) {
      if (!subs[i].enabled) continue;
      try {
        await SubscriptionManager.refresh(subs[i].id);
      } catch (e) {
        LogStore.push('订阅', subs[i].name + ' 更新失败: ' + (e instanceof Error ? e.message : String(e)));
      }
    }
  }

  /** 启动/回前台时检查到期订阅（间隔取设置） */
  static async checkDue(): Promise<void> {
    const hours: number = SettingsStore.get().subUpdateHours;
    if (hours <= 0) return;
    const subs: Subscription[] = loadAll();
    const now: number = Date.now();
    for (let i = 0; i < subs.length; i++) {
      if (!subs[i].enabled) continue;
      if (subs[i].lastUpdate === 0 || now - subs[i].lastUpdate > hours * 3600 * 1000) {
        try {
          await SubscriptionManager.refresh(subs[i].id);
        } catch (e) {
          // 静默
        }
      }
    }
  }
}
