// v2rayNG Harmony · 运行日志（老板铁律：第一版内置日志）
// 内存环形缓冲 + 同步落盘 filesDir/logs/v2rayng.log（尽力而为，失败不崩）
// VPN 扩展跨进程日志走 vpn_diag.txt（见 V2RayVpnExtension），本 Store 供 UI 进程。
import { fileIo as fs } from '@kit.CoreFileKit';

export interface LogLine {
  time: string;
  tag: string;
  msg: string;
}

const MAX_LINES = 800;
const lines: LogLine[] = [];
const listeners: Array<() => void> = [];
let logFilePath: string = '';

function nowStr(): string {
  const d: Date = new Date();
  const p = (n: number): string => (n < 10 ? '0' + n : '' + n);
  return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}

function filesDir(): string {
  const g: Record<string, Object> = globalThis as Object as Record<string, Object>;
  const ctx: Object | undefined = g['v2rayngAppContext'];
  if (ctx === undefined) return '';
  const holder: Record<string, Object> = ctx as Object as Record<string, Object>;
  return String(holder['filesDir'] ?? '');
}

/** EntryAbility 启动时调用：确定落盘路径并写一条启动标记 */
export function initLogFile(): void {
  const dir: string = filesDir();
  if (dir.length === 0) return;
  try {
    try {
      fs.mkdirSync(dir + '/logs');
    } catch (e) {
      // 已存在忽略
    }
    logFilePath = dir + '/logs/v2rayng.log';
  } catch (e) {
    logFilePath = '';
  }
}

function appendToFile(line: LogLine): void {
  if (logFilePath.length === 0) return;
  let file: fs.File | null = null;
  try {
    file = fs.openSync(logFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
    fs.writeSync(file.fd, line.time + ' [' + line.tag + '] ' + line.msg + '\n');
  } catch (e) {
    // 落盘失败静默（日志不能成为崩溃源）
  } finally {
    if (file !== null) {
      try {
        fs.closeSync(file);
      } catch (e2) {
        // 忽略
      }
    }
  }
}

function notify(): void {
  for (let i = 0; i < listeners.length; i++) {
    try {
      listeners[i]();
    } catch (e) {
      // 忽略监听器异常
    }
  }
}

export class LogStore {
  static push(tag: string, msg: string): void {
    const line: LogLine = { time: nowStr(), tag: tag, msg: msg };
    lines.push(line);
    if (lines.length > MAX_LINES) lines.splice(0, lines.length - MAX_LINES);
    appendToFile(line);
    notify();
  }

  static getAll(): LogLine[] {
    return lines.slice();
  }

  static exportText(): string {
    const out: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      out.push(lines[i].time + ' [' + lines[i].tag + '] ' + lines[i].msg);
    }
    // 追加 VPN 扩展诊断文件内容（跨进程）
    const dir: string = filesDir();
    if (dir.length > 0) {
      try {
        const diag: string = fs.readTextSync(dir + '/vpn_diag.txt', { encoding: 'utf-8' });
        out.push('---- vpn_diag.txt ----');
        out.push(diag);
      } catch (e) {
        // 无诊断文件忽略
      }
    }
    return out.join('\n');
  }

  static filePath(): string {
    return logFilePath;
  }

  static clear(): void {
    lines.length = 0;
    if (logFilePath.length > 0) {
      try {
        fs.unlinkSync(logFilePath);
      } catch (e) {
        // 忽略
      }
    }
    notify();
  }

  static subscribe(fn: () => void): void {
    listeners.push(fn);
  }

  static unsubscribe(fn: () => void): void {
    const idx: number = listeners.indexOf(fn);
    if (idx >= 0) listeners.splice(idx, 1);
  }
}
