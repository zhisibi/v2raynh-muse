// v2rayNG Harmony · Xray 配置生成
// 对照 Android: core/CoreConfigManager.kt + CoreOutboundBuilder.kt + assets/v2ray_config.json
// 纯 TS：零鸿蒙依赖。设置类型在本文件定义，SettingsStore 复用之（避免循环依赖写两套）。

import { ProfileItem } from './UriParser';

export type RoutingMode = 'rule' | 'global' | 'direct';

export interface AppSettings {
  socksPort: number;
  httpPort: number;
  routingMode: RoutingMode;
  enableUdp: boolean;
  sniffingEnabled: boolean;
  ipv6Enabled: boolean;
  localDns: string;
  remoteDns: string;
  subUpdateHours: number;
  tunEnabled: boolean;
  logLevel: string;
  /** 按应用代理（基础版）：off 不启用 / block 黑名单不走 VPN / allow 仅名单走 VPN */
  perAppMode: 'off' | 'block' | 'allow';
  /** 名单：包名逗号分隔，如 com.example.app,com.example.browser */
  perAppList: string;
}

export function defaultSettings(): AppSettings {
  const s: AppSettings = {
    socksPort: 10808,
    httpPort: 10809,
    routingMode: 'rule',
    enableUdp: true,
    sniffingEnabled: true,
    ipv6Enabled: true,
    localDns: '223.5.5.5',
    remoteDns: '1.1.1.1',
    subUpdateHours: 24,
    tunEnabled: true,
    logLevel: 'warning',
    perAppMode: 'off',
    perAppList: '',
  };
  return s;
}

export const CONFIG_FILE_NAME = 'xray_config.json';
export const TUN_ADDR_V4 = '172.19.0.1';
export const TUN_PREFIX_V4 = 30;
export const TUN_ADDR_V6 = 'fdfe:dcba:9876::1';
export const TUN_PREFIX_V6 = 126;
/** hev-socks5-tunnel 的 TUN 地址（与 VpnConfig 对齐，见 V2RayVpnExtension） */
export const HEV_TUN_NAME = 'hev-tun';

type JsonObj = Record<string, Object>;

function splitCsv(s: string): string[] {
  const out: string[] = [];
  const parts: string[] = s.split(',');
  for (let i = 0; i < parts.length; i++) {
    const t: string = parts[i].trim();
    if (t.length > 0) out.push(t);
  }
  return out;
}

function portNum(p: ProfileItem): number {
  const n: number = parseInt(p.serverPort, 10);
  return isNaN(n) ? 0 : n;
}

function tlsSettings(p: ProfileItem): JsonObj {
  const o: JsonObj = {};
  const sni: string = p.sni.length > 0 ? p.sni : (p.host.length > 0 ? p.host : p.server);
  o['serverName'] = sni;
  o['allowInsecure'] = p.insecure;
  if (p.alpn.length > 0) o['alpn'] = splitCsv(p.alpn);
  if (p.fingerPrint.length > 0) o['fingerprint'] = p.fingerPrint;
  if (p.echConfigList.length > 0) o['echConfigList'] = p.echConfigList;
  if (p.verifyPeerCertByName.length > 0) o['verifyPeerCertByName'] = p.verifyPeerCertByName;
  if (p.pinnedCA256.length > 0) o['pinnedPeerCertificateChainSha256'] = p.pinnedCA256;
  return o;
}

function realitySettings(p: ProfileItem): JsonObj {
  const o: JsonObj = {};
  o['serverName'] = p.sni;
  o['fingerprint'] = p.fingerPrint.length > 0 ? p.fingerPrint : 'chrome';
  o['publicKey'] = p.publicKey;
  o['shortId'] = p.shortId;
  o['spiderX'] = p.spiderX;
  if (p.mldsa65Verify.length > 0) o['mldsa65Verify'] = p.mldsa65Verify;
  return o;
}

/** populateTransportSettings + populateTlsSettings 等价；返回组装好的 streamSettings */
function buildStreamSettings(p: ProfileItem): JsonObj {
  const ss: JsonObj = {};
  const net: string = p.network.length > 0 ? p.network : 'tcp';
  ss['network'] = net;
  if (net === 'tcp') {
    const tcp: JsonObj = {};
    const header: JsonObj = {};
    header['type'] = p.headerType.length > 0 ? p.headerType : 'none';
    if (p.headerType === 'http') {
      const req: JsonObj = {};
      req['version'] = '1.1';
      req['method'] = 'GET';
      req['path'] = splitCsv(p.path.length > 0 ? p.path : '/');
      const headers: JsonObj = {};
      headers['Host'] = splitCsv(p.host);
      req['headers'] = headers;
      header['request'] = req;
    }
    tcp['header'] = header;
    ss['tcpSettings'] = tcp;
  } else if (net === 'kcp') {
    const kcp: JsonObj = {};
    kcp['mtu'] = 1350;
    kcp['tti'] = 50;
    kcp['uplinkCapacity'] = 12;
    kcp['downlinkCapacity'] = 100;
    kcp['congestion'] = false;
    kcp['readBufferSize'] = 2;
    kcp['writeBufferSize'] = 2;
    const header: JsonObj = {};
    header['type'] = p.headerType.length > 0 ? p.headerType : 'none';
    kcp['header'] = header;
    if (p.seed.length > 0) kcp['seed'] = p.seed;
    ss['kcpSettings'] = kcp;
  } else if (net === 'ws') {
    const ws: JsonObj = {};
    ws['path'] = p.path.length > 0 ? p.path : '/';
    if (p.host.length > 0) ws['host'] = p.host;
    const headers: JsonObj = {};
    if (p.host.length > 0) headers['Host'] = p.host;
    ws['headers'] = headers;
    ss['wsSettings'] = ws;
  } else if (net === 'httpupgrade') {
    const hu: JsonObj = {};
    hu['path'] = p.path.length > 0 ? p.path : '/';
    if (p.host.length > 0) hu['host'] = p.host;
    ss['httpupgradeSettings'] = hu;
  } else if (net === 'xhttp') {
    const xh: JsonObj = {};
    xh['path'] = p.path.length > 0 ? p.path : '/';
    if (p.host.length > 0) xh['host'] = p.host;
    if (p.xhttpMode.length > 0) xh['mode'] = p.xhttpMode;
    if (p.xhttpExtra.length > 0) {
      try {
        xh['extra'] = JSON.parse(p.xhttpExtra) as Object;
      } catch (e) {
        // extra 非 JSON 时原样字符串透传（内核会报错并由日志暴露）
        xh['extra'] = p.xhttpExtra;
      }
    }
    ss['xhttpSettings'] = xh;
  } else if (net === 'http' || net === 'h2') {
    ss['network'] = 'tcp';
    const http: JsonObj = {};
    http['host'] = splitCsv(p.host);
    http['path'] = p.path.length > 0 ? p.path : '/';
    ss['httpSettings'] = http;
    // Xray 的 h2 实际走 tcpSettings? 原版 v2rayNG 用 httpSettings + network=tcp 的
    // 历史形态；新版 Xray 亦兼容 network=xhttp 之外的 httpSettings 写法。
  } else if (net === 'grpc') {
    const grpc: JsonObj = {};
    grpc['serviceName'] = p.serviceName;
    if (p.authority.length > 0) grpc['authority'] = p.authority;
    grpc['multiMode'] = p.mode === 'multi';
    ss['grpcSettings'] = grpc;
  } else if (net === 'quic') {
    const quic: JsonObj = {};
    quic['security'] = p.quicSecurity.length > 0 ? p.quicSecurity : 'none';
    quic['key'] = p.quicKey;
    const header: JsonObj = {};
    header['type'] = p.headerType.length > 0 ? p.headerType : 'none';
    quic['header'] = header;
    ss['quicSettings'] = quic;
  } else if (net === 'hysteria') {
    const hy: JsonObj = {};
    hy['version'] = 2;
    if (p.password.length > 0) hy['auth'] = p.password;
    if (p.bandwidthDown.length > 0) hy['down'] = p.bandwidthDown;
    if (p.bandwidthUp.length > 0) hy['up'] = p.bandwidthUp;
    // obfs salamander / 端口跳跃：新版 Xray 用 finalmask 表达，尽力映射
    if (p.obfsPassword.length > 0 || p.portHopping.length > 0) {
      const fm: JsonObj = {};
      const udpArr: Object[] = [];
      if (p.obfsPassword.length > 0) {
        const mask: JsonObj = {};
        mask['type'] = 'salamander';
        const mset: JsonObj = {};
        mset['password'] = p.obfsPassword;
        mask['settings'] = mset;
        udpArr.push(mask);
      }
      if (p.portHopping.length > 0) {
        const hop: JsonObj = {};
        hop['type'] = 'udphop';
        const hset: JsonObj = {};
        hset['ports'] = p.portHopping;
        if (p.portHoppingInterval.length > 0) {
          const iv: number = parseInt(p.portHoppingInterval, 10);
          if (!isNaN(iv)) hset['interval'] = iv;
        }
        hop['settings'] = hset;
        udpArr.push(hop);
      }
      fm['udp'] = udpArr;
      ss['finalmask'] = fm;
    }
    ss['hysteriaSettings'] = hy;
  }
  // 安全层
  if (p.security === 'tls') {
    // hysteria2 在 Xray 中 security 字段为 tls 且需 tlsSettings
    ss['security'] = 'tls';
    ss['tlsSettings'] = tlsSettings(p);
  } else if (p.security === 'reality') {
    ss['security'] = 'reality';
    ss['realitySettings'] = realitySettings(p);
  } else {
    ss['security'] = 'none';
  }
  if (p.finalMask.length > 0 && net !== 'hysteria') {
    try {
      ss['finalmask'] = JSON.parse(p.finalMask) as Object;
    } catch (e) {
      // finalMask 非 JSON 时忽略（原版为结构化表单，分享链接里是 JSON 字符串）
    }
  }
  return ss;
}

function buildProxyOutbound(p: ProfileItem): JsonObj {
  const out: JsonObj = {};
  out['tag'] = 'proxy';
  const settings: JsonObj = {};
  const mux: JsonObj = {};
  mux['enabled'] = false;
  mux['concurrency'] = -1;
  out['mux'] = mux;

  if (p.configType === 'WIREGUARD') {
    out['protocol'] = 'wireguard';
    settings['secretKey'] = p.secretKey;
    const addrs: string[] = p.localAddress.length > 0 ? splitCsv(p.localAddress) : ['172.16.0.2/32'];
    settings['address'] = addrs;
    settings['mtu'] = p.mtu > 0 ? p.mtu : 1420;
    if (p.remoteDNS.length > 0) settings['domainStrategy'] = 'ForceIP';
    const peer: JsonObj = {};
    peer['publicKey'] = p.publicKey;
    if (p.preSharedKey.length > 0) peer['preSharedKey'] = p.preSharedKey;
    peer['endpoint'] = (p.server.indexOf(':') >= 0 ? '[' + p.server + ']' : p.server) + ':' + p.serverPort;
    const peers: Object[] = [];
    peers.push(peer);
    settings['peers'] = peers;
    if (p.reserved.length > 0) {
      const res: number[] = [];
      const parts: string[] = p.reserved.split(',');
      for (let i = 0; i < parts.length; i++) {
        const n: number = parseInt(parts[i].trim(), 10);
        if (!isNaN(n)) res.push(n);
      }
      if (res.length > 0) settings['reserved'] = res;
    }
    out['settings'] = settings;
    if (p.finalMask.length > 0) {
      const wss: JsonObj = {};
      try {
        wss['finalmask'] = JSON.parse(p.finalMask) as Object;
        out['streamSettings'] = wss;
      } catch (e) {
        // 忽略
      }
    }
    return out;
  }

  if (p.configType === 'HYSTERIA2') {
    out['protocol'] = 'hysteria';
    settings['address'] = p.server;
    settings['port'] = portNum(p);
    settings['version'] = 2;
    out['settings'] = settings;
    const hp: ProfileItem = p;
    // hysteria 传输在 streamSettings 中以 network=hysteria 表达
    const savedNet: string = hp.network;
    hp.network = 'hysteria';
    out['streamSettings'] = buildStreamSettings(hp);
    hp.network = savedNet;
    return out;
  }

  // 通用 address/port 型协议
  settings['address'] = p.server;
  settings['port'] = portNum(p);
  settings['level'] = 8;
  if (p.configType === 'VMESS') {
    out['protocol'] = 'vmess';
    settings['id'] = p.password;
    settings['security'] = p.method.length > 0 ? p.method : 'auto';
  } else if (p.configType === 'VLESS') {
    out['protocol'] = 'vless';
    settings['id'] = p.password;
    settings['encryption'] = p.method.length > 0 ? p.method : 'none';
    if (p.flow.length > 0) settings['flow'] = p.flow;
  } else if (p.configType === 'SHADOWSOCKS') {
    out['protocol'] = 'shadowsocks';
    settings['password'] = p.password;
    settings['method'] = p.method;
  } else if (p.configType === 'TROJAN') {
    out['protocol'] = 'trojan';
    settings['password'] = p.password;
    if (p.flow.length > 0) settings['flow'] = p.flow;
  } else if (p.configType === 'SOCKS') {
    out['protocol'] = 'socks';
    if (p.username.length > 0) {
      settings['user'] = p.username;
      settings['pass'] = p.password;
    }
  } else if (p.configType === 'HTTP') {
    out['protocol'] = 'http';
    if (p.username.length > 0) {
      settings['user'] = p.username;
      settings['pass'] = p.password;
    }
  } else {
    out['protocol'] = 'socks';
  }
  out['settings'] = settings;
  if (p.configType !== 'SOCKS' && p.configType !== 'HTTP') {
    out['streamSettings'] = buildStreamSettings(p);
  } else if (p.configType === 'HTTP' && p.security === 'tls') {
    const hss: JsonObj = {};
    hss['security'] = 'tls';
    hss['tlsSettings'] = tlsSettings(p);
    out['streamSettings'] = hss;
  }
  return out;
}

/** 由节点 + 设置生成完整 Xray 配置 JSON 字符串 */
export function buildXrayConfig(p: ProfileItem, s: AppSettings): string {
  if (p.configType === 'CUSTOM') {
    // 用户完整 JSON 原样使用（仅校验可解析）
    try {
      JSON.parse(p.customConfig);
      return p.customConfig;
    } catch (e) {
      // 落到空配置，下方内核启动会报错并写入日志
    }
  }
  const root: JsonObj = {};

  const log: JsonObj = {};
  log['loglevel'] = s.logLevel.length > 0 ? s.logLevel : 'warning';
  root['log'] = log;

  // DNS 架构对照原版 v2rayNG（CoreConfigManager.kt，v1.1.2 修正）：
  // dns.tag='dns-module'——内部 DNS 模块产生的流量带 inboundTag 'dns-module'，
  // 由路由规则 {inboundTag:[dns-module] -> proxy} 整体经代理出站（远程 DNS 是
  // IP 地址、无鸡生蛋问题）；国内服务器条目带 per-server tag 'dns-domestic'，
  // 由 {inboundTag:[dns-domestic] -> direct} 直连。切勿加无 inboundTag 的
  // port:53 catch-all 规则：那会把 DNS 模块自己的上游查询也劫持回 dns 出站，
  // 造成解析递归黑洞（v1.1.0/1.1.1 真机无法联网的根因）。
  const dns: JsonObj = {};
  const hosts: JsonObj = {};
  dns['hosts'] = hosts;
  const servers: Object[] = [];
  const local: JsonObj = {};
  local['address'] = s.localDns;
  local['port'] = 53;
  local['domains'] = ['geosite:cn'];
  local['skipFallback'] = true;
  local['tag'] = 'dns-domestic';
  servers.push(local);
  const remote: JsonObj = {};
  remote['address'] = s.remoteDns;
  remote['port'] = 53;
  remote['domains'] = ['geosite:geolocation-!cn'];
  remote['expectIPs'] = [];
  servers.push(remote);
  // 兜底：远程 DNS
  servers.push(s.remoteDns);
  dns['servers'] = servers;
  dns['queryStrategy'] = s.ipv6Enabled ? 'UseIP' : 'UseIPv4';
  dns['tag'] = 'dns-module';
  root['dns'] = dns;

  const inbounds: Object[] = [];
  const socksIn: JsonObj = {};
  socksIn['tag'] = 'socks';
  socksIn['port'] = s.socksPort;
  socksIn['listen'] = '127.0.0.1';
  socksIn['protocol'] = 'socks';
  const socksSet: JsonObj = {};
  socksSet['auth'] = 'noauth';
  socksSet['udp'] = s.enableUdp;
  socksSet['userLevel'] = 8;
  if (s.ipv6Enabled) socksSet['ip'] = '127.0.0.1';
  socksIn['settings'] = socksSet;
  if (s.sniffingEnabled) {
    const sniff: JsonObj = {};
    sniff['enabled'] = true;
    sniff['destOverride'] = ['http', 'tls', 'quic'];
    sniff['routeOnly'] = true;
    socksIn['sniffing'] = sniff;
  }
  inbounds.push(socksIn);
  const httpIn: JsonObj = {};
  httpIn['tag'] = 'http';
  httpIn['port'] = s.httpPort;
  httpIn['listen'] = '127.0.0.1';
  httpIn['protocol'] = 'http';
  const httpSet: JsonObj = {};
  httpSet['userLevel'] = 8;
  httpIn['settings'] = httpSet;
  if (s.sniffingEnabled) {
    const sniff2: JsonObj = {};
    sniff2['enabled'] = true;
    sniff2['destOverride'] = ['http', 'tls', 'quic'];
    sniff2['routeOnly'] = true;
    httpIn['sniffing'] = sniff2;
  }
  inbounds.push(httpIn);
  root['inbounds'] = inbounds;

  const outbounds: Object[] = [];
  outbounds.push(buildProxyOutbound(p));
  const direct: JsonObj = {};
  direct['tag'] = 'direct';
  direct['protocol'] = 'freedom';
  const dset: JsonObj = {};
  dset['domainStrategy'] = s.ipv6Enabled ? 'UseIP' : 'UseIPv4';
  direct['settings'] = dset;
  outbounds.push(direct);
  const block: JsonObj = {};
  block['tag'] = 'block';
  block['protocol'] = 'blackhole';
  const bset: JsonObj = {};
  const bresp: JsonObj = {};
  bresp['type'] = 'http';
  bset['response'] = bresp;
  block['settings'] = bset;
  outbounds.push(block);
  // DNS 出站只有一个（tag=dns-out，对照原版 TAG_DNS_OUT）：
  // 供 hev 劫持规则 {inboundTag:[socks], port:53 -> dns-out} 使用。
  const dnsOut: JsonObj = {};
  dnsOut['tag'] = 'dns-out';
  dnsOut['protocol'] = 'dns';
  outbounds.push(dnsOut);
  root['outbounds'] = outbounds;

  const routing: JsonObj = {};
  routing['domainStrategy'] = 'AsIs';
  const rules: Object[] = [];
  const addRule = (outbound: string, ip: string[], domain: string[], port: string): void => {
    const r: JsonObj = {};
    r['type'] = 'field';
    r['outboundTag'] = outbound;
    if (ip.length > 0) r['ip'] = ip;
    if (domain.length > 0) r['domain'] = domain;
    if (port.length > 0) r['port'] = port;
    rules.push(r);
  };
  if (s.tunEnabled) {
    // 规则①（仅 TUN，对照原版 hev DNS 劫持）：hev 经 socks 入站送来的 53 端口
    // 查询交给 dns 出站处理。不要带 network 字段（与原版一致）。
    const dnsRule: JsonObj = {};
    dnsRule['type'] = 'field';
    dnsRule['inboundTag'] = ['socks'];
    dnsRule['port'] = '53';
    dnsRule['outboundTag'] = 'dns-out';
    rules.push(dnsRule);
  }
  // 规则②：国内 DNS 服务器（per-server tag dns-domestic）产生的查询直连
  const domesticRule: JsonObj = {};
  domesticRule['type'] = 'field';
  domesticRule['inboundTag'] = ['dns-domestic'];
  domesticRule['outboundTag'] = 'direct';
  rules.push(domesticRule);
  // 规则③：内部 DNS 模块的其余上游查询（远程 DNS）整体经代理出站
  const moduleRule: JsonObj = {};
  moduleRule['type'] = 'field';
  moduleRule['inboundTag'] = ['dns-module'];
  moduleRule['outboundTag'] = 'proxy';
  rules.push(moduleRule);
  if (s.routingMode === 'global') {
    addRule('proxy', ['0.0.0.0/0', '::/0'], [], '');
  } else if (s.routingMode === 'direct') {
    addRule('direct', ['0.0.0.0/0', '::/0'], [], '');
  } else {
    // rule：私有/国内直连，其余代理（对照 v2rayNG 规则模式 + Loyalsoldier 规则集思路）
    addRule('direct', ['geoip:private'], [], '');
    addRule('direct', [], ['geosite:cn'], '');
    addRule('direct', ['geoip:cn'], [], '');
    addRule('proxy', [], ['geosite:geolocation-!cn'], '');
    addRule('proxy', ['0.0.0.0/0', '::/0'], [], '');
  }
  routing['rules'] = rules;
  root['routing'] = routing;

  const policy: JsonObj = {};
  const levels: JsonObj = {};
  const l8: JsonObj = {};
  l8['handshake'] = 4;
  l8['connIdle'] = 300;
  l8['uplinkOnly'] = 1;
  l8['downlinkOnly'] = 1;
  levels['8'] = l8;
  policy['levels'] = levels;
  const sys: JsonObj = {};
  sys['statsOutboundUplink'] = true;
  sys['statsOutboundDownlink'] = true;
  policy['system'] = sys;
  root['policy'] = policy;

  const stats: JsonObj = {};
  root['stats'] = stats;

  return JSON.stringify(root, null, 2);
}
