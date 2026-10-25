// v2rayNG Harmony · 连接编排：生成 Xray 配置 -> 写文件 -> 拉起 VPN 扩展 -> 轮询状态
import { fileIo as fs } from '@kit.CoreFileKit';
import { notificationManager } from '@kit.NotificationKit';
import { ServerStore } from '../model/ServerStore';
import { SettingsStore } from '../model/SettingsStore';
import { buildXrayConfig, CONFIG_FILE_NAME } from '../model/XrayConfig';
import { LogStore } from '../model/LogStore';
import { VpnService } from './VpnService';
import { ensureAssets } from '../model/AssetInstaller';

const STATUS_FILE = 'vpn_status.json';
export const PERAPP_FILE_NAME = 'vpn_perapp.json';

/** vpn_perapp.json 结构（扩展进程读取，UI 进程 Preferences 它读不到） */
export interface PerAppConfig {
  mode: string; // off | block | allow
  list: string[]; // 包名列表
}

export interface VpnStatus {
  state: string;
  error: string;
  step: string;
}

interface FilesDirHolder {
  filesDir: string;
}

function filesDir(): string {
  const g: Record<string, Object> = globalThis as Object as Record<string, Object>;
  const ctx: Object | undefined = g['v2rayngAppContext'];
  if (ctx === undefined) return '';
  return (ctx as FilesDirHolder).filesDir;
}

export function writeTextFile(path: string, text: string): void {
  let file: fs.File | null = null;
  try {
    file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, text);
  } finally {
    if (file !== null) fs.closeSync(file);
  }
}

function readStatus(): VpnStatus {
  try {
    const raw: string = fs.readTextSync(filesDir() + '/' + STATUS_FILE, { encoding: 'utf-8' });
    const parsed: VpnStatus = JSON.parse(raw) as VpnStatus;
    return parsed;
  } catch (e) {
    const unknown: VpnStatus = { state: 'unknown', error: '', step: '' };
    return unknown;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve: () => void) => setTimeout(() => resolve(), ms));
}

const NOTIFY_ID: number = 1001;

/** 连接成功通知（基础通知；未授权/失败静默，不影响连接流程） */
async function publishConnectedNotification(nodeName: string): Promise<void> {
  try {
    const content: notificationManager.NotificationContent = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: 'v2rayNG 已连接',
        text: nodeName,
        additionalText: '',
      },
    };
    const req: notificationManager.NotificationRequest = {
      id: NOTIFY_ID,
      content: content,
    };
    await notificationManager.publish(req);
  } catch (e) {
    // 通知未授权或系统拒绝时静默（不记错误日志，避免噪音）
  }
}

function cancelConnectedNotification(): void {
  try {
    notificationManager.cancel(NOTIFY_ID).catch(() => {
      // 忽略
    });
  } catch (e) {
    // 忽略
  }
}

export class ConnectManager {
  static async connect(): Promise<string> {
    const selected = ServerStore.getSelected();
    if (selected === undefined) {
      if (ServerStore.count() === 0) {
        return '还没有节点：先去「节点」页导入/添加，或去「订阅」页添加订阅';
      }
      return '请先在「节点」页选择一个节点';
    }
    const settings = SettingsStore.get();
    // 连接前兜底释放 geo 数据（启动时未完成/失败时在此补齐）
    await ensureAssets();
    const configJson: string = buildXrayConfig(selected.profile, settings);
    try {
      writeTextFile(filesDir() + '/' + CONFIG_FILE_NAME, configJson);
    } catch (e) {
      return '写入配置文件失败';
    }
    LogStore.push('连接', '正在连接 ' + selected.profile.remarks + '（' + selected.profile.configType + '）模式=' +
      (settings.tunEnabled ? 'TUN' : '仅代理'));
    // 按应用代理配置写文件供扩展读取（扩展与 UI 不在同一进程）
    try {
      const perApp: PerAppConfig = {
        mode: settings.perAppMode,
        list: settings.perAppList.split(',')
          .map((x: string) => x.trim())
          .filter((x: string) => x.length > 0),
      };
      writeTextFile(filesDir() + '/' + PERAPP_FILE_NAME, JSON.stringify(perApp));
    } catch (e) {
      LogStore.push('连接', '写入按应用代理配置失败（忽略，用默认）');
    }
    try {
      fs.unlinkSync(filesDir() + '/' + STATUS_FILE);
    } catch (e) {
      // 不存在则忽略
    }
    try {
      fs.unlinkSync(filesDir() + '/vpn_diag.txt');
    } catch (e) {
      // 不存在则忽略
    }
    try {
      await VpnService.connect(settings.tunEnabled);
    } catch (e) {
      return '拉起 VPN 扩展失败: ' + (e instanceof Error ? e.message : String(e));
    }
    // 等待扩展就绪（最长 12 秒：首次含系统 VPN 授权弹窗时间偏紧，真机若超时看 step 定位）
    for (let i = 0; i < 24; i++) {
      await sleep(500);
      const st: VpnStatus = readStatus();
      if (st.state === 'running') {
        LogStore.push('连接', '已连接');
        publishConnectedNotification(selected.profile.remarks).catch(() => {
          // 忽略
        });
        return '';
      }
      if (st.state === 'error') {
        LogStore.push('连接', '连接失败(step=' + st.step + '): ' + st.error);
        return st.error || '内核启动失败';
      }
    }
    const last: VpnStatus = readStatus();
    return '连接超时：扩展未在 12 秒内就绪（最后状态 ' + last.state + '，step=' +
      (last.step.length > 0 ? last.step : '无') + (last.error.length > 0 ? '，' + last.error : '') + '）';
  }

  static disconnect(): void {
    VpnService.disconnect();
    cancelConnectedNotification();
    LogStore.push('连接', '已断开');
  }

  static status(): 'running' | 'starting' | 'stopped' | 'error' | 'unknown' {
    const st: VpnStatus = readStatus();
    if (st.state === 'running') return 'running';
    if (st.state === 'starting') return 'starting';
    if (st.state === 'error') return 'error';
    if (st.state === 'stopped') return 'stopped';
    return 'unknown';
  }

  static lastError(): string {
    return readStatus().error;
  }

  static lastStep(): string {
    return readStatus().step;
  }
}
