// v2rayNG Harmony · 共享样式与小工具（白底 + 蓝色主色，参考 v2rayNG 安卓版）
import { socket } from '@kit.NetworkKit';
import { pasteboard } from '@kit.BasicServicesKit';

export class Pal {
  static bg: string = '#FFFFFF';
  static card: string = '#F5F7FA';
  static text: string = '#12242C';
  static sub: string = '#5B6D74';
  static accent: string = '#1976D2';
  static accentSoft: string = '#E3F0FA';
  static chip: string = '#E7EEF3';
  static good: string = '#1E8A4C';
  static warn: string = '#A86A00';
  static bad: string = '#C0392B';
  static line: string = '#DCE6EC';
}

export function fmtBytes(n: number): string {
  if (n < 1024) return n + ' B';
  if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KB';
  if (n < 1024 * 1024 * 1024) return (n / 1024 / 1024).toFixed(1) + ' MB';
  return (n / 1024 / 1024 / 1024).toFixed(2) + ' GB';
}

export function fmtTime(ts: number): string {
  if (ts <= 0) return '从未';
  const d: Date = new Date(ts);
  const p = (x: number): string => (x < 10 ? '0' + x : '' + x);
  return (d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
}

export function fmtExpire(ts: number): string {
  if (ts <= 0) return '未知';
  const d: Date = new Date(ts);
  return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate();
}

/** 复制文本到系统剪贴板（日志导出/分享链接用） */
export async function copyToClipboard(text: string): Promise<boolean> {
  try {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    await board.setData(data);
    return true;
  } catch (e) {
    return false;
  }
}

/** 读取剪贴板文本（导入用），失败返回 '' */
export async function readClipboard(): Promise<string> {
  try {
    const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    const data: pasteboard.PasteData = await board.getData();
    if (data.getRecordCount() > 0) {
      return data.getPrimaryText();
    }
    return '';
  } catch (e) {
    return '';
  }
}

/** 直连 TCP 握手延迟（ms），失败 -1。内核未运行时测速用（不精确，仅连通性） */
export async function tcpPing(host: string, port: number, timeoutMs: number): Promise<number> {
  if (port <= 0 || host.length === 0) return -1;
  const isV6: boolean = host.indexOf(':') >= 0;
  const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
  const t0: number = Date.now();
  try {
    await tcp.connect({
      address: { address: host, port: port, family: isV6 ? 2 : 1 },
      timeout: timeoutMs,
    });
    const ms: number = Date.now() - t0;
    try {
      await tcp.close();
    } catch (e) {
      // 忽略
    }
    return ms;
  } catch (e) {
    try {
      await tcp.close();
    } catch (e2) {
      // 忽略
    }
    return -1;
  }
}
