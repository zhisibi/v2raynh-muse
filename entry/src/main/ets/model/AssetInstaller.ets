// v2rayNG Harmony · Xray 资产释放
// HAP 内 rawfile/xray/{geoip.dat,geosite.dat} 需释放到 filesDir/xray_assets/，
// Xray 桥以 XRAY_LOCATION_ASSET=<assetDir> 启动，规则模式的 geoip:/geosite: 规则依赖这两文件。
// UI 进程在 EntryAbility.onCreate 与每次连接前调用 ensureAssets()（幂等、并发合并）。
import { fileIo as fs } from '@kit.CoreFileKit';
import { LogStore } from './LogStore';

interface RawFileManager {
  getRawFileContent(path: string): Promise<Uint8Array>;
}

interface AppContextHolder {
  filesDir: string;
  resourceManager: RawFileManager;
}

const ASSET_FILES: string[] = ['geoip.dat', 'geosite.dat'];
const RAW_PREFIX = 'xray/';

let inflight: Promise<boolean> | undefined = undefined;

function appContext(): AppContextHolder | undefined {
  const g: Record<string, Object> = globalThis as Object as Record<string, Object>;
  const ctx: Object | undefined = g['v2rayngAppContext'];
  if (ctx === undefined) return undefined;
  return ctx as AppContextHolder;
}

export function assetDirPath(): string {
  const ctx = appContext();
  if (ctx === undefined) return '';
  return ctx.filesDir + '/xray_assets';
}

function fileExistsWithSize(path: string): boolean {
  try {
    const stat = fs.statSync(path);
    return stat.size > 0;
  } catch (e) {
    return false;
  }
}

async function copyOne(ctx: AppContextHolder, name: string): Promise<void> {
  const dest = ctx.filesDir + '/xray_assets/' + name;
  if (fileExistsWithSize(dest)) return;
  const data: Uint8Array = await ctx.resourceManager.getRawFileContent(RAW_PREFIX + name);
  let file: fs.File | null = null;
  try {
    file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    const CHUNK = 1024 * 1024;
    let offset = 0;
    while (offset < data.length) {
      const end = Math.min(offset + CHUNK, data.length);
      const part: Uint8Array = data.subarray(offset, end);
      const buf: ArrayBuffer = part.buffer.slice(part.byteOffset, part.byteOffset + part.byteLength) as ArrayBuffer;
      fs.writeSync(file.fd, buf);
      offset = end;
    }
  } finally {
    if (file !== null) fs.closeSync(file);
  }
  LogStore.push('资产', name + ' 已释放 (' + data.length + ' 字节)');
}

async function doEnsure(): Promise<boolean> {
  const ctx = appContext();
  if (ctx === undefined) return false;
  try {
    try {
      fs.mkdirSync(ctx.filesDir + '/xray_assets');
    } catch (e) {
      // 已存在
    }
    for (let i = 0; i < ASSET_FILES.length; i++) {
      await copyOne(ctx, ASSET_FILES[i]);
    }
    return true;
  } catch (e) {
    LogStore.push('资产', '释放 geo 数据失败: ' + (e instanceof Error ? e.message : String(e)));
    return false;
  }
}

/** 确保 geoip.dat/geosite.dat 已释放到 xray_assets；多次调用合并为一次。 */
export function ensureAssets(): Promise<boolean> {
  if (inflight !== undefined) return inflight;
  const p: Promise<boolean> = doEnsure();
  inflight = p;
  p.then(() => {
    if (inflight === p) inflight = undefined;
  }).catch(() => {
    if (inflight === p) inflight = undefined;
  });
  return p;
}
