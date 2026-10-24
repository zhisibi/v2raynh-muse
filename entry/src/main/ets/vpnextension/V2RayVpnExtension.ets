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
import { protectProcessNetDyn, setAllowedApplicationsDyn } from './DynCompat';
import {
  CONFIG_FILE_NAME, TUN_ADDR_V4, TUN_PREFIX_V4, TUN_ADDR_V6, TUN_PREFIX_V6,
} from '../model/XrayConfig';

const TAG = 'V2RayVpn';
const DOMAIN = 0xff01;
const STATUS_FILE = 'vpn_status.json';
const PERAPP_FILE = 'vpn_perapp.json';
const PARAM_MODE = 'v2rayng_mode';
const MTU = 1500;

interface PerAppFile {
  mode: string;
  list: string[];
}

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
      // 先拆隧道/核心（不写状态），最后写 error——否则 stopVpn 的 stopped 会把
      // error 覆盖掉，UI 永远等不到失败状态（v1.1.0 修正）。
      this.teardown();
      this.writeStatus('error', msg, this.currentStep);
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

    // 按应用代理（基础版）：读 ConnectManager 写的 vpn_perapp.json；
    // 缺失/解析失败时保持 v1.0 行为（仅自身 blocked 防回环）。
    let perAppMode: string = 'off';
    let perAppBundles: string[] = [];
    try {
      const rawPer: string = fs.readTextSync(this.context.filesDir + '/' + PERAPP_FILE,
        { encoding: 'utf-8' });
      const parsedPer: PerAppFile = JSON.parse(rawPer) as PerAppFile;
      perAppMode = parsedPer.mode;
      perAppBundles = parsedPer.list;
      this.diag('perapp mode=' + perAppMode + ' list=' + perAppBundles.length + ' 个');
    } catch (e) {
      // 无配置文件则默认 off
    }
    const selfBundle: string = this.context.applicationInfo.name;
    let blockedApps: string[] = [selfBundle];
    if (perAppMode === 'block') {
      for (let i = 0; i < perAppBundles.length; i++) {
        if (blockedApps.indexOf(perAppBundles[i]) < 0) blockedApps.push(perAppBundles[i]);
      }
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
      blockedApplications: blockedApps,
    };
    if (perAppMode === 'allow' && perAppBundles.length > 0) {
      // allow 模式：仅名单内应用进隧道；自身不入名单，核心出站直连防回环。
      // allowedApplications 不在 API 18 的 VpnConfig 类型定义中，经 DynCompat
      // 动态写入；运行时不支持时 diag 留痕（此时退化为全量进隧道）。
      const okAllow: boolean = setAllowedApplicationsDyn(vpnConfig, perAppBundles);
      this.diag('perapp allow 动态写入 allowedApplications=' + okAllow);
      vpnConfig.blockedApplications = [];
    }
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
    // hev TUN->SOCKS：失败必须诚实报错（v1.0 时返回 false 仍报 running，
    // TUN 里流量无处可去却显示已连接——v1.1.0 起直接抛错走 error 状态）。
    this.step('tun-start');
    const tunOk: boolean = startTun(socksPort, MTU);
    this.diag('startTun(hev) 返回 ' + tunOk);
    if (!tunOk) {
      throw new Error('TUN 转发启动失败：hev 未就绪（startTun=false），详见诊断日志');
    }
    this.writeStatus('running', '', 'running');
    this.diag('完成: Xray 核心运行中，TUN 转发已启动');
  }

  /** 拆隧道与核心（不写状态文件），供 onDestroy 与启动失败路径共用 */
  private teardown(): void {
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
  }

  private stopVpn(): void {
    this.teardown();
    this.writeStatus('stopped', '', 'stopped');
    this.diag('VPN 已停止');
  }
}
