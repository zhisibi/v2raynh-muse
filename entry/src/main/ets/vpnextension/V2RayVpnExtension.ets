// v2rayNG Harmony · VPN 隧道扩展
// 流程（TUN 模式）：读 filesDir/xray_config.json -> 写 hev 配置 -> 建 TUN（双栈全路由）
//   -> protectProcessNet 防回环 -> attachTunFd -> startXray -> startTun(hev TUN->SOCKS)
//   -> 写 vpn_status.json(running, step 标记全程)
// 仅代理模式（want 参数 v2rayng_mode=proxy）：不建 TUN，只 startXray，应用外流量需手动指代理。
// 停止：onDestroy -> stopTun -> stopXray -> destroy TUN（反序）。
// 状态文件写入必须带 TRUNC：澜舟教训——无 TRUNC 时旧残留字节损坏 JSON，UI 永远读不到状态。
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { attachTunFd, startXray, stopXray, startTun, stopTun, lastError } from '../model/CoreBridge';
import { protectProcessNetDyn } from './DynCompat';
import {
  CONFIG_FILE_NAME, TUN_ADDR_V4, TUN_PREFIX_V4, TUN_ADDR_V6, TUN_PREFIX_V6,
} from '../model/XrayConfig';

const TAG = 'V2RayVpn';
const DOMAIN = 0xff01;
const STATUS_FILE = 'vpn_status.json';
const PARAM_MODE = 'v2rayng_mode';
const MTU = 1500;

interface VpnStatus {
  state: string;
  error: string;
  step: string;
}

function logInfo(msg: string): void {
  hilog.info(DOMAIN, TAG, '%{public}s', msg);
}

function logError(msg: string): void {
  hilog.error(DOMAIN, TAG, '%{public}s', msg);
}

export default class V2RayVpnExtension extends VpnExtensionAbility {
  private connection: vpnExtension.VpnConnection | undefined = undefined;
  private tunMode: boolean = true;
  private currentStep: string = '';

  onCreate(want?: Want): void {
    const params: Record<string, Object> | undefined = want?.parameters;
    if (params !== undefined) {
      const mode: Object | undefined = params[PARAM_MODE];
      this.tunMode = mode === undefined || String(mode) !== 'proxy';
    }
    this.diag('onCreate mode=' + (this.tunMode ? 'tun' : 'proxy'));
    this.writeStatus('starting', '', 'config');
    this.startVpn().catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : '未知错误';
      logError('启动失败: ' + msg);
      this.diag('失败 step=' + this.currentStep + ': ' + msg);
      this.writeStatus('error', msg, this.currentStep);
      this.stopVpn();
    });
  }

  onDestroy(): void {
    this.stopVpn();
  }

  private configPath(): string {
    return this.context.filesDir + '/' + CONFIG_FILE_NAME;
  }

  private assetDir(): string {
    return this.context.filesDir + '/xray_assets';
  }

  private statusPath(): string {
    return this.context.filesDir + '/' + STATUS_FILE;
  }

  private writeStatus(state: string, error: string, step: string): void {
    this.currentStep = step;
    const status: VpnStatus = { state: state, error: error, step: step };
    const text: string = JSON.stringify(status);
    let file: fs.File | null = null;
    try {
      file = fs.openSync(this.statusPath(), fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, text);
    } catch (e) {
      // 忽略
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

  private step(mark: string): void {
    this.writeStatus('starting', '', mark);
    this.diag('step:' + mark);
  }

  /** 诊断日志（追加写文件，UI 侧可读——扩展与 UI 不在同一进程） */
  private diag(msg: string): void {
    const d: Date = new Date();
    const p = (n: number): string => (n < 10 ? '0' + n : '' + n);
    const line: string =
      p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds()) + ' ' + msg + '\n';
    let file: fs.File | null = null;
    try {
      file = fs.openSync(this.context.filesDir + '/vpn_diag.txt',
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, line);
    } catch (e) {
      // 忽略
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e2) {
          // 忽略
        }
      }
    }
    logInfo(msg);
  }

  private async startVpn(): Promise<void> {
    if (this.connection !== undefined) return;
    this.step('config');
    let configText: string = '';
    try {
      configText = fs.readTextSync(this.configPath(), { encoding: 'utf-8' });
    } catch (e) {
      throw new Error('读取配置文件失败，请先在应用内点击连接');
    }
    if (configText.trim().length === 0) throw new Error('配置文件为空');
    try {
      fs.mkdirSync(this.assetDir());
    } catch (e) {
      // 已存在则忽略
    }

    if (!this.tunMode) {
      // 仅代理模式：只起核心
      this.step('core-starting');
      const okProxy: boolean = startXray(configText, this.assetDir());
      if (!okProxy) throw new Error('内核启动失败: ' + lastError());
      this.writeStatus('running', '', 'core-ok');
      this.diag('完成: 仅代理模式，核心运行中');
      return;
    }

    // TUN 模式：VpnConfig 形态对齐澜舟真机验证版
    const vpnConfig: vpnExtension.VpnConfig = {
      mtu: MTU,
      addresses: [
        { address: { address: TUN_ADDR_V4, family: 1 }, prefixLength: TUN_PREFIX_V4 },
        { address: { address: TUN_ADDR_V6, family: 2 }, prefixLength: TUN_PREFIX_V6 },
      ],
      routes: [
        {
          interface: 'vpn-tun',
          destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
          gateway: { address: TUN_ADDR_V4, family: 1 },
          hasGateway: false,
          isDefaultRoute: true,
        },
        {
          interface: 'vpn-tun',
          destination: { address: { address: '::', family: 2 }, prefixLength: 0 },
          gateway: { address: TUN_ADDR_V6, family: 2 },
          hasGateway: false,
          isDefaultRoute: true,
        },
      ],
      dnsAddresses: [TUN_ADDR_V4, TUN_ADDR_V6],
      isIPv4Accepted: true,
      isIPv6Accepted: true,
      isBlocking: false,
      blockedApplications: [this.context.applicationInfo.name],
    };
    this.step('tun-create');
    const connection: vpnExtension.VpnConnection = vpnExtension.createVpnConnection(this.context);
    let tunFd: number = -1;
    try {
      tunFd = await connection.create(vpnConfig);
    } catch (e) {
      const em: string = e instanceof Error ? e.message : '未知错误';
      this.diag('TUN 建立失败: ' + em);
      throw new Error('TUN 建立失败: ' + em);
    }
    this.connection = connection;
    this.step('tun-ok');
    this.diag('TUN 就绪 fd=' + tunFd);
    try {
      protectProcessNetDyn(connection);
      this.diag('protectProcessNet 已调用');
    } catch (e) {
      this.diag('protectProcessNet 调用异常');
    }
    if (!attachTunFd(tunFd, MTU)) {
      throw new Error('attachTunFd 失败');
    }
    this.step('attach-ok');

    this.step('core-starting');
    const ok: boolean = startXray(configText, this.assetDir());
    this.diag('startXray 返回 ' + ok + (ok ? '' : ' lastError=' + lastError()));
    if (!ok) {
      throw new Error('内核启动失败: ' + lastError());
    }

    // hev TUN->SOCKS：符号缺失/未编译时返回 false，记录但不中断——
    // 核心已运行，系统代理（SOCKS 10808）可用，全局 TUN 待真机补齐 hev 后生效。
    // SOCKS 端口从配置 JSON 解析（扩展进程无 UI 的 Preferences 上下文，不能依赖 SettingsStore）
    let socksPort: number = 10808;
    try {
      const parsedCfg: Record<string, Object> = JSON.parse(configText) as Record<string, Object>;
      const inb: Object[] = parsedCfg['inbounds'] as Object[];
      for (let i = 0; i < inb.length; i++) {
        const one: Record<string, Object> = inb[i] as Object as Record<string, Object>;
        if (String(one['tag'] ?? '') === 'socks') socksPort = Number(one['port'] ?? 10808);
      }
    } catch (e) {
      // 用默认 10808
    }
    const tunOk: boolean = startTun(socksPort, MTU);
    this.diag('startTun(hev) 返回 ' + tunOk + (tunOk ? '' : '（hev 未就绪，TUN 转发未生效）'));
    this.writeStatus('running', tunOk ? '' : 'hev-unavailable', 'running');
    this.diag('完成: Xray 核心运行中');
  }

  private stopVpn(): void {
    try {
      stopTun();
    } catch (e) {
      // 忽略
    }
    try {
      stopXray();
    } catch (e) {
      // 忽略
    }
    const c: vpnExtension.VpnConnection | undefined = this.connection;
    this.connection = undefined;
    if (c !== undefined) {
      c.destroy().catch(() => {
        // 忽略
      });
    }
    this.writeStatus('stopped', '', 'stopped');
    this.diag('VPN 已停止');
  }
}
