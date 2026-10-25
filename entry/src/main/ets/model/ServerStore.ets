// v2rayNG Harmony · 节点存储（内存 + Preferences 持久化）
// 内部直接保存 ProfileItem（对照 Android 的 MMKV profile 存储）。
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { ProfileItem, profileFromJson } from './UriParser';

const PREF_NAME = 'v2rayng_servers';
const KEY_NODES = 'nodes';
const KEY_SELECTED = 'selected_id';

let pref: preferences.Preferences | undefined = undefined;
let cache: ProfileItem[] | undefined = undefined;
/** id 索引：用 addedTime+server 组合不稳定，故另加一列本地 id 映射（下标与 cache 同步） */
let ids: string[] = [];
let selectedId: string = '';

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

function genId(): string {
  return 'n' + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
}

export interface StoredNode {
  id: string;
  profile: ProfileItem;
  delay: number;
}

let delays: Record<string, number> = {};

function loadAll(): ProfileItem[] {
  if (cache !== undefined) return cache;
  cache = [];
  ids = [];
  delays = {};
  const p: preferences.Preferences | undefined = getPref();
  if (p !== undefined) {
    try {
      const raw: string = p.getSync(KEY_NODES, '[]') as string;
      const arr: StoredNode[] = JSON.parse(raw) as StoredNode[];
      for (let i = 0; i < arr.length; i++) {
        const prof: ProfileItem = profileFromJson(arr[i].profile as Object as Record<string, Object>);
        cache.push(prof);
        ids.push(arr[i].id);
        delays[arr[i].id] = arr[i].delay;
      }
      selectedId = p.getSync(KEY_SELECTED, '') as string;
    } catch (e) {
      cache = [];
      ids = [];
    }
  }
  return cache;
}

function persist(): void {
  const p: preferences.Preferences | undefined = getPref();
  if (p === undefined || cache === undefined) return;
  try {
    const arr: StoredNode[] = [];
    for (let i = 0; i < cache.length; i++) {
      const sn: StoredNode = { id: ids[i], profile: cache[i], delay: Number(delays[ids[i]] ?? -1) };
      arr.push(sn);
    }
    p.putSync(KEY_NODES, JSON.stringify(arr));
    p.putSync(KEY_SELECTED, selectedId);
    p.flush();
  } catch (e) {
    // 忽略
  }
}

export interface ServerEntry {
  id: string;
  profile: ProfileItem;
  delay: number;
}

export class ServerStore {
  static getEntries(): ServerEntry[] {
    const nodes: ProfileItem[] = loadAll();
    const out: ServerEntry[] = [];
    for (let i = 0; i < nodes.length; i++) {
      const e: ServerEntry = { id: ids[i], profile: nodes[i], delay: Number(delays[ids[i]] ?? -1) };
      out.push(e);
    }
    return out;
  }

  static getAll(): ProfileItem[] {
    return loadAll().slice();
  }

  static add(profile: ProfileItem): string {
    const nodes: ProfileItem[] = loadAll();
    const id: string = genId();
    nodes.push(profile);
    ids.push(id);
    delays[id] = -1;
    persist();
    return id;
  }

  static update(id: string, profile: ProfileItem): void {
    const nodes: ProfileItem[] = loadAll();
    const idx: number = ids.indexOf(id);
    if (idx >= 0) {
      nodes[idx] = profile;
      persist();
    }
  }

  static remove(id: string): void {
    const nodes: ProfileItem[] = loadAll();
    const idx: number = ids.indexOf(id);
    if (idx >= 0) {
      nodes.splice(idx, 1);
      ids.splice(idx, 1);
      delays[id] = -1; // ArkTS 不支持 delete；残留键不参与持久化（按节点遍历）
      if (selectedId === id) selectedId = '';
      persist();
    }
  }

  static clearBySubscription(subId: string): void {
    const nodes: ProfileItem[] = loadAll();
    const keepP: ProfileItem[] = [];
    const keepI: string[] = [];
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].subscriptionId !== subId) {
        keepP.push(nodes[i]);
        keepI.push(ids[i]);
      } else {
        delays[ids[i]] = -1; // 同上，不用 delete
      }
    }
    cache = keepP;
    ids = keepI;
    if (selectedId.length > 0 && ids.indexOf(selectedId) < 0) selectedId = '';
    persist();
  }

  static addMany(profiles: ProfileItem[]): number {
    let n: number = 0;
    for (let i = 0; i < profiles.length; i++) {
      ServerStore.add(profiles[i]);
      n++;
    }
    return n;
  }

  static setSelected(id: string): void {
    selectedId = id;
    persist();
  }

  static getSelectedId(): string {
    loadAll();
    return selectedId;
  }

  static getSelected(): ServerEntry | undefined {
    const entries: ServerEntry[] = ServerStore.getEntries();
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].id === selectedId) return entries[i];
    }
    return undefined;
  }

  static getById(id: string): ServerEntry | undefined {
    const entries: ServerEntry[] = ServerStore.getEntries();
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].id === id) return entries[i];
    }
    return undefined;
  }

  static setDelay(id: string, ms: number): void {
    delays[id] = ms;
    persist();
  }

  static count(): number {
    return loadAll().length;
  }

  /** 备份导出：全部节点 JSON */
  static exportJson(): string {
    return JSON.stringify(ServerStore.getEntries(), null, 2);
  }

  /** 备份快照（原始存储形态：id/profile/delay），供备份与恢复页整体导出 */
  static snapshotRaw(): StoredNode[] {
    const nodes: ProfileItem[] = loadAll();
    const out: StoredNode[] = [];
    for (let i = 0; i < nodes.length; i++) {
      const sn: StoredNode = { id: ids[i], profile: nodes[i], delay: Number(delays[ids[i]] ?? -1) };
      out.push(sn);
    }
    return out;
  }

  /** 备份恢复：整体替换全部节点（入参为 JSON 解析出的普通对象数组），返回恢复条数 */
  static restoreRaw(rawNodes: Object[], selected: string): number {
    const newCache: ProfileItem[] = [];
    const newIds: string[] = [];
    const newDelays: Record<string, number> = {};
    for (let i = 0; i < rawNodes.length; i++) {
      const holder: Record<string, Object> = rawNodes[i] as Object as Record<string, Object>;
      const profObj: Object | undefined = holder['profile'];
      if (profObj === undefined) continue;
      const prof: ProfileItem = profileFromJson(profObj as Object as Record<string, Object>);
      let id: string = String(holder['id'] ?? '');
      if (id.length === 0 || newIds.indexOf(id) >= 0) id = genId();
      newCache.push(prof);
      newIds.push(id);
      const d: number = Number(holder['delay'] ?? -1);
      newDelays[id] = isNaN(d) ? -1 : d;
    }
    cache = newCache;
    ids = newIds;
    delays = newDelays;
    selectedId = newIds.indexOf(selected) >= 0 ? selected : '';
    persist();
    return newCache.length;
  }

  static importProfiles(profiles: ProfileItem[]): number {
    return ServerStore.addMany(profiles);
  }
}
