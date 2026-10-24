// v2rayNG Harmony · 全协议分享链接解析/生成
// 对照 Android: fmt/*.kt (VmessFmt/VlessFmt/ShadowsocksFmt/TrojanFmt/WireguardFmt/
// Hysteria2Fmt/SocksFmt/FmtBase) + dto/entities/ProfileItem.kt + dto/VmessQRCode.kt
// 纯 TS：零鸿蒙依赖，可用 tsc strict 在 Node 下冒烟测试。

export type ConfigType =
  'VMESS' | 'VLESS' | 'SHADOWSOCKS' | 'TROJAN' | 'WIREGUARD' |
  'HYSTERIA2' | 'SOCKS' | 'HTTP' | 'CUSTOM';

/** 对齐 Kotlin ProfileItem（字段名保持一致，便于 JSON 持久化互通理解） */
export interface ProfileItem {
  configVersion: number;
  configType: ConfigType;
  subscriptionId: string;
  addedTime: number;
  remarks: string;
  description: string;
  server: string;
  serverPort: string;
  password: string;
  method: string;
  flow: string;
  username: string;
  network: string;
  headerType: string;
  host: string;
  path: string;
  seed: string;
  quicSecurity: string;
  quicKey: string;
  mode: string;
  serviceName: string;
  authority: string;
  xhttpMode: string;
  xhttpExtra: string;
  finalMask: string;
  security: string;
  sni: string;
  alpn: string;
  fingerPrint: string;
  insecure: boolean;
  echConfigList: string;
  verifyPeerCertByName: string;
  pinnedCA256: string;
  publicKey: string;
  shortId: string;
  spiderX: string;
  mldsa65Verify: string;
  secretKey: string;
  preSharedKey: string;
  localAddress: string;
  reserved: string;
  mtu: number;
  remoteDNS: string;
  obfsPassword: string;
  portHopping: string;
  portHoppingInterval: string;
  bandwidthDown: string;
  bandwidthUp: string;
  /** CUSTOM 类型：用户粘贴的完整 Xray JSON 文本 */
  customConfig: string;
}

export function createProfile(configType: ConfigType): ProfileItem {
  const p: ProfileItem = {
    configVersion: 4,
    configType: configType,
    subscriptionId: '',
    addedTime: Date.now(),
    remarks: '',
    description: '',
    server: '',
    serverPort: '',
    password: '',
    method: '',
    flow: '',
    username: '',
    network: 'tcp',
    headerType: '',
    host: '',
    path: '',
    seed: '',
    quicSecurity: '',
    quicKey: '',
    mode: '',
    serviceName: '',
    authority: '',
    xhttpMode: '',
    xhttpExtra: '',
    finalMask: '',
    security: '',
    sni: '',
    alpn: '',
    fingerPrint: '',
    insecure: false,
    echConfigList: '',
    verifyPeerCertByName: '',
    pinnedCA256: '',
    publicKey: '',
    shortId: '',
    spiderX: '',
    mldsa65Verify: '',
    secretKey: '',
    preSharedKey: '',
    localAddress: '',
    reserved: '',
    mtu: 0,
    remoteDNS: '',
    obfsPassword: '',
    portHopping: '',
    portHoppingInterval: '',
    bandwidthDown: '',
    bandwidthUp: '',
    customConfig: '',
  };
  return p;
}

/** 从任意 JSON 对象安全补齐 ProfileItem（持久化读回用） */
export function profileFromJson(o: Record<string, Object>): ProfileItem {
  const t: string = String(o['configType'] ?? 'VMESS');
  let ct: ConfigType = 'VMESS';
  const all: ConfigType[] = ['VMESS', 'VLESS', 'SHADOWSOCKS', 'TROJAN', 'WIREGUARD', 'HYSTERIA2', 'SOCKS', 'HTTP', 'CUSTOM'];
  for (let i = 0; i < all.length; i++) {
    if (all[i] === t) ct = all[i];
  }
  const p: ProfileItem = createProfile(ct);
  const s = (k: string): string => String(o[k] ?? '');
  p.configVersion = Number(o['configVersion'] ?? 4);
  p.subscriptionId = s('subscriptionId');
  p.addedTime = Number(o['addedTime'] ?? 0);
  p.remarks = s('remarks'); p.description = s('description');
  p.server = s('server'); p.serverPort = s('serverPort');
  p.password = s('password'); p.method = s('method'); p.flow = s('flow');
  p.username = s('username'); p.network = s('network') || 'tcp';
  p.headerType = s('headerType'); p.host = s('host'); p.path = s('path');
  p.seed = s('seed'); p.quicSecurity = s('quicSecurity'); p.quicKey = s('quicKey');
  p.mode = s('mode'); p.serviceName = s('serviceName'); p.authority = s('authority');
  p.xhttpMode = s('xhttpMode'); p.xhttpExtra = s('xhttpExtra'); p.finalMask = s('finalMask');
  p.security = s('security'); p.sni = s('sni'); p.alpn = s('alpn');
  p.fingerPrint = s('fingerPrint');
  p.insecure = Boolean(o['insecure'] ?? false);
  p.echConfigList = s('echConfigList'); p.verifyPeerCertByName = s('verifyPeerCertByName');
  p.pinnedCA256 = s('pinnedCA256'); p.publicKey = s('publicKey'); p.shortId = s('shortId');
  p.spiderX = s('spiderX'); p.mldsa65Verify = s('mldsa65Verify');
  p.secretKey = s('secretKey'); p.preSharedKey = s('preSharedKey');
  p.localAddress = s('localAddress'); p.reserved = s('reserved');
  p.mtu = Number(o['mtu'] ?? 0); p.remoteDNS = s('remoteDNS');
  p.obfsPassword = s('obfsPassword'); p.portHopping = s('portHopping');
  p.portHoppingInterval = s('portHoppingInterval');
  p.bandwidthDown = s('bandwidthDown'); p.bandwidthUp = s('bandwidthUp');
  p.customConfig = s('customConfig');
  return p;
}

// ---------- base64（纯实现，兼容 url-safe / 缺 padding / UTF-8） ----------
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export function b64Decode(input: string): string {
  let s: string = input.replace(/\s/g, '').replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4 !== 0) s += '=';
  let out: string = '';
  let i: number = 0;
  while (i < s.length) {
    const a: number = B64.indexOf(s.charAt(i++));
    const b: number = B64.indexOf(s.charAt(i++));
    const c: number = B64.indexOf(s.charAt(i++));
    const d: number = B64.indexOf(s.charAt(i++));
    if (a < 0 || b < 0) break;
    const n: number = (a << 18) | (b << 12) | ((c < 0 ? 0 : c) << 6) | (d < 0 ? 0 : d);
    out += String.fromCharCode((n >> 16) & 255);
    if (c >= 0) out += String.fromCharCode((n >> 8) & 255);
    if (d >= 0) out += String.fromCharCode(n & 255);
  }
  try {
    return decodeURIComponent(escape(out));
  } catch (e) {
    return out;
  }
}

export function b64Encode(input: string, urlSafe: boolean = false): string {
  let bytes: string = input;
  try {
    bytes = unescape(encodeURIComponent(input));
  } catch (e) {
    bytes = input;
  }
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const a: number = bytes.charCodeAt(i++);
    const hasB: boolean = i < bytes.length;
    const b: number = hasB ? bytes.charCodeAt(i++) : 0;
    const hasC: boolean = i < bytes.length;
    const c: number = hasC ? bytes.charCodeAt(i++) : 0;
    const n: number = (a << 16) | (b << 8) | c;
    out += B64.charAt((n >> 18) & 63);
    out += B64.charAt((n >> 12) & 63);
    out += hasB ? B64.charAt((n >> 6) & 63) : '=';
    out += hasC ? B64.charAt(n & 63) : '=';
  }
  if (urlSafe) {
    out = out.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }
  return out;
}

// ---------- URI 基础工具 ----------
function safeDec(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch (e) {
    return s;
  }
}

function enc(s: string): string {
  return encodeURIComponent(s);
}

export function parseQuery(qs: string): Record<string, string> {
  const q: Record<string, string> = {};
  const s: string = qs.startsWith('?') ? qs.substring(1) : qs;
  if (s.length === 0) return q;
  const pairs: string[] = s.split('&');
  for (let i = 0; i < pairs.length; i++) {
    const kv: string[] = pairs[i].split('=');
    if (kv.length >= 1 && kv[0].length > 0) {
      q[safeDec(kv[0])] = kv.length > 1 ? safeDec(kv.slice(1).join('=')) : '';
    }
  }
  return q;
}

export interface Authority {
  user: string;
  pass: string;
  host: string;
  port: number;
}

export function parseHostPort(hostPort: string): Authority | null {
  let host: string = '';
  let portStr: string = '';
  if (hostPort.startsWith('[')) {
    const end: number = hostPort.indexOf(']');
    if (end < 0) return null;
    host = hostPort.substring(1, end);
    const rest: string = hostPort.substring(end + 1);
    if (rest.startsWith(':')) portStr = rest.substring(1);
  } else {
    const cIdx: number = hostPort.lastIndexOf(':');
    if (cIdx >= 0) {
      host = hostPort.substring(0, cIdx);
      portStr = hostPort.substring(cIdx + 1);
    } else {
      host = hostPort;
    }
  }
  if (host.length === 0) return null;
  const port: number = parseInt(portStr, 10);
  const a: Authority = { user: '', pass: '', host: host, port: isNaN(port) ? 0 : port };
  return a;
}

/** 解析 scheme:// 之后的主体：返回 authority 与 query、fragment */
export interface StdUri {
  auth: Authority;
  query: Record<string, string>;
  remarks: string;
  rawUserInfo: string;
}

export function parseStdUri(body: string): StdUri | null {
  let rest: string = body;
  let remarks: string = '';
  const hashIdx: number = rest.indexOf('#');
  if (hashIdx >= 0) {
    remarks = safeDec(rest.substring(hashIdx + 1));
    rest = rest.substring(0, hashIdx);
  }
  let queryStr: string = '';
  const qIdx: number = rest.indexOf('?');
  if (qIdx >= 0) {
    queryStr = rest.substring(qIdx + 1);
    rest = rest.substring(0, qIdx);
  }
  const atIdx: number = rest.lastIndexOf('@');
  let rawUserInfo: string = '';
  let hostPort: string = rest;
  if (atIdx >= 0) {
    rawUserInfo = rest.substring(0, atIdx);
    hostPort = rest.substring(atIdx + 1);
  }
  const hp: Authority | null = parseHostPort(hostPort);
  if (hp === null) return null;
  let user: string = '';
  let pass: string = '';
  if (rawUserInfo.length > 0) {
    const cIdx: number = rawUserInfo.indexOf(':');
    if (cIdx >= 0) {
      user = safeDec(rawUserInfo.substring(0, cIdx));
      pass = safeDec(rawUserInfo.substring(cIdx + 1));
    } else {
      user = safeDec(rawUserInfo);
    }
  }
  const auth: Authority = { user: user, pass: pass, host: hp.host, port: hp.port };
  const out: StdUri = { auth: auth, query: parseQuery(queryStr), remarks: remarks, rawUserInfo: rawUserInfo };
  return out;
}

function ipv6Wrap(host: string): string {
  if (host.indexOf(':') >= 0 && !host.startsWith('[')) return '[' + host + ']';
  return host;
}

/** FmtBase.getItemFormQuery 等价 */
function fillFromQuery(p: ProfileItem, q: Record<string, string>): void {
  const g = (k: string): string => String(q[k] ?? '');
  p.network = g('type') || 'tcp';
  p.headerType = g('headerType');
  p.host = g('host');
  p.path = g('path');
  p.seed = g('seed');
  const mtu: number = parseInt(g('mtu'), 10);
  if (!isNaN(mtu)) p.mtu = mtu;
  p.quicSecurity = g('quicSecurity');
  p.quicKey = g('key');
  p.mode = g('mode');
  p.serviceName = g('serviceName');
  p.authority = g('authority');
  p.xhttpMode = g('mode');
  p.xhttpExtra = g('extra');
  p.finalMask = g('fm');
  const sec: string = g('security');
  p.security = (sec === 'tls' || sec === 'reality') ? sec : '';
  p.insecure = g('insecure') === '1' || g('allowInsecure') === '1' || g('allow_insecure') === '1';
  p.sni = g('sni');
  p.fingerPrint = g('fp');
  p.alpn = g('alpn');
  p.echConfigList = g('ech');
  p.verifyPeerCertByName = g('vcn');
  p.pinnedCA256 = g('pcs');
  p.publicKey = g('pbk');
  p.shortId = g('sid');
  p.spiderX = g('spx');
  p.mldsa65Verify = g('pqv');
  p.flow = g('flow');
}

/** FmtBase.getQueryDic 等价：有序键值对数组 */
function queryPairs(p: ProfileItem, includeSecurity: boolean): Array<Array<string>> {
  const pairs: Array<Array<string>> = [];
  const add = (k: string, v: string): void => {
    if (v.length > 0) pairs.push([k, v]);
  };
  if (includeSecurity) pairs.push(['security', p.security.length > 0 ? p.security : 'none']);
  add('sni', p.sni); add('alpn', p.alpn); add('ech', p.echConfigList);
  add('vcn', p.verifyPeerCertByName); add('pcs', p.pinnedCA256); add('fp', p.fingerPrint);
  add('pbk', p.publicKey); add('sid', p.shortId); add('spx', p.spiderX);
  add('pqv', p.mldsa65Verify); add('flow', p.flow); add('fm', p.finalMask);
  if (p.security === 'tls') {
    pairs.push(['insecure', p.insecure ? '1' : '0']);
    pairs.push(['allowInsecure', p.insecure ? '1' : '0']);
  }
  const net: string = p.network.length > 0 ? p.network : 'tcp';
  pairs.push(['type', net === 'h2' ? 'http' : net]);
  if (net === 'tcp' || net === 'kcp') {
    pairs.push(['headerType', p.headerType.length > 0 ? p.headerType : 'none']);
    if (net === 'tcp') add('host', p.host);
    if (net === 'kcp') add('seed', p.seed);
  } else if (net === 'ws' || net === 'httpupgrade') {
    add('host', p.host); add('path', p.path);
  } else if (net === 'xhttp') {
    add('host', p.host); add('path', p.path); add('mode', p.xhttpMode); add('extra', p.xhttpExtra);
  } else if (net === 'http' || net === 'h2') {
    add('host', p.host); add('path', p.path);
  } else if (net === 'grpc') {
    add('mode', p.mode); add('authority', p.authority); add('serviceName', p.serviceName);
  }
  return pairs;
}

function buildUri(scheme: string, userInfo: string, p: ProfileItem, pairs: Array<Array<string>>): string {
  let qs: string = '';
  if (pairs.length > 0) {
    const parts: string[] = [];
    for (let i = 0; i < pairs.length; i++) {
      parts.push(pairs[i][0] + '=' + enc(pairs[i][1]));
    }
    qs = '?' + parts.join('&');
  }
  return scheme + enc(userInfo) + '@' + ipv6Wrap(p.server) + ':' + p.serverPort + qs +
    '#' + enc(p.remarks);
}

// ---------- VMess ----------
interface VmessJson {
  v?: string; ps?: string; add?: string; port?: string; id?: string; aid?: string;
  scy?: string; net?: string; type?: string; host?: string; path?: string;
  tls?: string; sni?: string; alpn?: string; fp?: string; insecure?: string;
  vcn?: string; pcs?: string;
}

function parseVmess(uri: string): ProfileItem | null {
  const body: string = uri.substring('vmess://'.length);
  // URL 式（标准）vmess：含 ? 与 &
  if (body.indexOf('?') > 0 && body.indexOf('&') > 0) {
    const std: StdUri | null = parseStdUri(body);
    if (std === null || std.auth.port <= 0) return null;
    const p: ProfileItem = createProfile('VMESS');
    p.remarks = std.remarks.length > 0 ? std.remarks : 'none';
    p.server = std.auth.host;
    p.serverPort = String(std.auth.port);
    p.password = std.auth.user;
    p.method = 'auto';
    fillFromQuery(p, std.query);
    const encQ: string = String(std.query['encryption'] ?? '');
    if (encQ.length > 0) p.method = encQ;
    return p;
  }
  const decoded: string = b64Decode(body.split('#')[0]);
  if (decoded.length === 0) return null;
  let j: VmessJson = {};
  try {
    j = JSON.parse(decoded) as VmessJson;
  } catch (e) {
    return null;
  }
  if (!j.add || !j.port || !j.id || !j.net) return null;
  const p: ProfileItem = createProfile('VMESS');
  p.remarks = String(j.ps ?? '');
  p.server = String(j.add);
  p.serverPort = String(j.port);
  p.password = String(j.id);
  p.method = String(j.scy ?? '').length > 0 ? String(j.scy) : 'auto';
  p.network = String(j.net);
  p.headerType = String(j.type ?? '');
  p.host = String(j.host ?? '');
  p.path = String(j.path ?? '');
  if (p.network === 'kcp') {
    p.seed = p.path;
  } else if (p.network === 'grpc') {
    p.mode = p.headerType;
    p.serviceName = p.path;
    p.authority = p.host;
  }
  p.security = String(j.tls ?? '');
  p.sni = String(j.sni ?? '');
  p.fingerPrint = String(j.fp ?? '');
  p.alpn = String(j.alpn ?? '');
  p.insecure = String(j.insecure ?? '') === '1';
  p.verifyPeerCertByName = String(j.vcn ?? '');
  p.pinnedCA256 = String(j.pcs ?? '');
  return p;
}

function vmessToUri(p: ProfileItem): string {
  const j: Record<string, string> = {};
  j['v'] = '2';
  j['ps'] = p.remarks;
  j['add'] = p.server;
  j['port'] = p.serverPort;
  j['id'] = p.password;
  j['aid'] = '0';
  j['scy'] = p.method;
  j['net'] = p.network.length > 0 ? p.network : 'tcp';
  j['type'] = p.headerType;
  j['host'] = p.host;
  j['path'] = p.path;
  if (p.network === 'kcp') j['path'] = p.seed;
  if (p.network === 'grpc') {
    j['type'] = p.mode;
    j['path'] = p.serviceName;
    j['host'] = p.authority;
  }
  j['tls'] = p.security;
  j['sni'] = p.sni;
  j['alpn'] = p.alpn;
  j['fp'] = p.fingerPrint;
  j['insecure'] = p.insecure ? '1' : '0';
  j['vcn'] = p.verifyPeerCertByName;
  j['pcs'] = p.pinnedCA256;
  return 'vmess://' + b64Encode(JSON.stringify(j));
}

// ---------- VLESS / Trojan / Socks / HTTP ----------
function parseVless(uri: string): ProfileItem | null {
  const std: StdUri | null = parseStdUri(uri.substring('vless://'.length));
  if (std === null || std.auth.port <= 0) return null;
  const p: ProfileItem = createProfile('VLESS');
  p.remarks = std.remarks.length > 0 ? std.remarks : 'none';
  p.server = std.auth.host;
  p.serverPort = String(std.auth.port);
  p.password = std.auth.user;
  p.method = String(std.query['encryption'] ?? '') || 'none';
  fillFromQuery(p, std.query);
  return p;
}

function parseTrojan(uri: string): ProfileItem | null {
  const std: StdUri | null = parseStdUri(uri.substring('trojan://'.length));
  if (std === null || std.auth.port <= 0) return null;
  const p: ProfileItem = createProfile('TROJAN');
  p.remarks = std.remarks.length > 0 ? std.remarks : 'none';
  p.server = std.auth.host;
  p.serverPort = String(std.auth.port);
  p.password = std.auth.user;
  fillFromQuery(p, std.query);
  if (p.security.length === 0) p.security = 'tls';
  return p;
}

function parseSocks(uri: string, schemeLen: number): ProfileItem | null {
  const std: StdUri | null = parseStdUri(uri.substring(schemeLen));
  if (std === null || std.auth.port <= 0) return null;
  const p: ProfileItem = createProfile('SOCKS');
  p.remarks = std.remarks.length > 0 ? std.remarks : 'none';
  p.server = std.auth.host;
  p.serverPort = String(std.auth.port);
  // SIP 式：userInfo 整体 base64(user:pass)
  if (std.auth.pass.length === 0 && std.auth.user.length > 0 && std.rawUserInfo.indexOf(':') < 0) {
    const dec: string = b64Decode(std.rawUserInfo);
    const ci: number = dec.indexOf(':');
    if (ci >= 0) {
      p.username = dec.substring(0, ci);
      p.password = dec.substring(ci + 1);
    } else {
      p.username = std.auth.user;
    }
  } else {
    p.username = std.auth.user;
    p.password = std.auth.pass;
  }
  return p;
}

function parseHttpProxy(uri: string): ProfileItem | null {
  const scheme: string = uri.startsWith('https://') ? 'https://' : 'http://';
  const std: StdUri | null = parseStdUri(uri.substring(scheme.length));
  if (std === null || std.auth.port <= 0) return null;
  const p: ProfileItem = createProfile('HTTP');
  p.remarks = std.remarks.length > 0 ? std.remarks : 'none';
  p.server = std.auth.host;
  p.serverPort = String(std.auth.port);
  p.username = std.auth.user;
  p.password = std.auth.pass;
  if (scheme === 'https://') p.security = 'tls';
  return p;
}

// ---------- Shadowsocks ----------
function parseSs(uri: string): ProfileItem | null {
  let body: string = uri.substring('ss://'.length);
  let remarks: string = '';
  const hashIdx: number = body.indexOf('#');
  if (hashIdx >= 0) {
    remarks = safeDec(body.substring(hashIdx + 1));
    body = body.substring(0, hashIdx);
  }
  let queryStr: string = '';
  const qIdx: number = body.indexOf('?');
  if (qIdx >= 0) {
    queryStr = body.substring(qIdx + 1);
    body = body.substring(0, qIdx);
  }
  const query: Record<string, string> = parseQuery(queryStr);
  let method: string = '';
  let password: string = '';
  let hostPort: string = '';
  const atIdx: number = body.lastIndexOf('@');
  if (atIdx >= 0) {
    const userInfo: string = body.substring(0, atIdx);
    hostPort = body.substring(atIdx + 1);
    if (userInfo.indexOf(':') >= 0) {
      const ci: number = userInfo.indexOf(':');
      method = safeDec(userInfo.substring(0, ci));
      password = safeDec(userInfo.substring(ci + 1));
    } else {
      const dec: string = b64Decode(userInfo);
      const ci: number = dec.indexOf(':');
      if (ci < 0) return null;
      method = dec.substring(0, ci);
      password = dec.substring(ci + 1);
    }
  } else {
    // legacy：整体 base64(method:password@host:port)
    const dec: string = b64Decode(body);
    const aIdx: number = dec.lastIndexOf('@');
    if (aIdx < 0) return null;
    const up: string = dec.substring(0, aIdx);
    hostPort = dec.substring(aIdx + 1);
    const ci: number = up.indexOf(':');
    if (ci < 0) return null;
    method = up.substring(0, ci);
    password = up.substring(ci + 1);
  }
  const hp: Authority | null = parseHostPort(hostPort);
  if (hp === null || hp.port <= 0) return null;
  const p: ProfileItem = createProfile('SHADOWSOCKS');
  p.remarks = remarks.length > 0 ? remarks : 'none';
  p.server = hp.host;
  p.serverPort = String(hp.port);
  p.method = method.toLowerCase();
  p.password = password;
  const plugin: string = String(query['plugin'] ?? '');
  if (plugin.indexOf('obfs=http') >= 0) {
    const parts: string[] = plugin.split(';');
    for (let i = 0; i < parts.length; i++) {
      const kv: string[] = parts[i].split('=');
      if (kv.length === 2 && kv[0] === 'obfs-host') p.host = kv[1];
      if (kv.length === 2 && kv[0] === 'path') p.path = kv[1];
    }
    p.network = 'tcp';
    p.headerType = 'http';
  }
  return p;
}

// ---------- WireGuard ----------
function parseWireguard(uri: string): ProfileItem | null {
  const body: string = uri.indexOf('://') >= 0 ? uri.substring(uri.indexOf('://') + 3) : uri;
  const std: StdUri | null = parseStdUri(body);
  if (std === null || std.auth.port <= 0) return null;
  const q: Record<string, string> = std.query;
  const p: ProfileItem = createProfile('WIREGUARD');
  p.remarks = std.remarks.length > 0 ? std.remarks : 'none';
  p.server = std.auth.host;
  p.serverPort = String(std.auth.port);
  p.secretKey = std.auth.user;
  p.localAddress = String(q['address'] ?? '') || '172.16.0.2/32';
  p.publicKey = String(q['publickey'] ?? '');
  p.preSharedKey = String(q['presharedkey'] ?? '');
  const mtu: number = parseInt(String(q['mtu'] ?? '1420'), 10);
  p.mtu = isNaN(mtu) ? 1420 : mtu;
  p.remoteDNS = String(q['dns'] ?? '') || '1.1.1.1';
  p.reserved = String(q['reserved'] ?? '') || '0,0,0';
  p.finalMask = String(q['fm'] ?? q['finalmask'] ?? '');
  return p;
}

/** WireGuard .conf 文本解析（对照 WireguardFmt.parseWireguardConfFile） */
export function parseWireguardConf(text: string): ProfileItem | null {
  const p: ProfileItem = createProfile('WIREGUARD');
  const iface: Record<string, string> = {};
  const peer: Record<string, string> = {};
  let section: string = '';
  const lines: string[] = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i].trim();
    if (line.length === 0 || line.startsWith('#')) continue;
    if (line.toLowerCase().startsWith('[interface]')) { section = 'i'; continue; }
    if (line.toLowerCase().startsWith('[peer]')) { section = 'p'; continue; }
    const eq: number = line.indexOf('=');
    if (eq < 0 || section.length === 0) continue;
    const k: string = line.substring(0, eq).trim().toLowerCase();
    const v: string = line.substring(eq + 1).trim();
    if (section === 'i') iface[k] = v; else peer[k] = v;
  }
  p.secretKey = String(iface['privatekey'] ?? '');
  p.localAddress = String(iface['address'] ?? '') || '172.16.0.2/32';
  const mtu: number = parseInt(String(iface['mtu'] ?? '1420'), 10);
  p.mtu = isNaN(mtu) ? 1420 : mtu;
  p.remoteDNS = String(iface['dns'] ?? '') || '1.1.1.1';
  p.publicKey = String(peer['publickey'] ?? '');
  p.preSharedKey = String(peer['presharedkey'] ?? '');
  const endpoint: string = String(peer['endpoint'] ?? '');
  const hp: Authority | null = parseHostPort(endpoint);
  if (hp !== null) {
    p.server = hp.host;
    p.serverPort = String(hp.port);
  }
  p.reserved = String(peer['reserved'] ?? '') || '0,0,0';
  p.remarks = 'WireGuard';
  if (p.secretKey.length === 0 || p.server.length === 0) return null;
  return p;
}

// ---------- Hysteria2 ----------
function parseHysteria2(uri: string): ProfileItem | null {
  const body: string = uri.substring(uri.indexOf('://') + 3);
  const std: StdUri | null = parseStdUri(body);
  if (std === null || std.auth.port <= 0) return null;
  const q: Record<string, string> = std.query;
  const p: ProfileItem = createProfile('HYSTERIA2');
  p.remarks = std.remarks.length > 0 ? std.remarks : 'none';
  p.server = std.auth.host;
  p.serverPort = String(std.auth.port);
  p.password = std.auth.user;
  p.security = 'tls';
  p.network = 'hysteria';
  fillFromQuery(p, q);
  p.security = String(q['security'] ?? '') || 'tls';
  p.network = 'hysteria';
  p.obfsPassword = String(q['obfs-password'] ?? '');
  p.portHopping = String(q['mport'] ?? '');
  p.pinnedCA256 = String(q['pinSHA256'] ?? '') || p.pinnedCA256;
  p.bandwidthDown = String(q['down'] ?? '');
  p.bandwidthUp = String(q['up'] ?? '');
  return p;
}

// ---------- 入口 ----------
export function parseUri(raw: string): ProfileItem | null {
  const uri: string = raw.trim();
  if (uri.length === 0) return null;
  const lower: string = uri.toLowerCase();
  try {
    if (lower.startsWith('vmess://')) return parseVmess(uri);
    if (lower.startsWith('vless://')) return parseVless(uri);
    if (lower.startsWith('ss://')) return parseSs(uri);
    if (lower.startsWith('trojan://')) return parseTrojan(uri);
    if (lower.startsWith('wireguard://') || lower.startsWith('wg://')) return parseWireguard(uri);
    if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) return parseHysteria2(uri);
    if (lower.startsWith('socks5://')) return parseSocks(uri, 'socks5://'.length);
    if (lower.startsWith('socks4://')) return parseSocks(uri, 'socks4://'.length);
    if (lower.startsWith('socks://')) return parseSocks(uri, 'socks://'.length);
    if (lower.startsWith('https://') || lower.startsWith('http://')) return parseHttpProxy(uri);
    if (uri.startsWith('{')) {
      const p: ProfileItem = createProfile('CUSTOM');
      p.remarks = '自定义配置';
      p.customConfig = uri;
      return p;
    }
    if (uri.indexOf('[Interface]') >= 0) return parseWireguardConf(uri);
  } catch (e) {
    return null;
  }
  return null;
}

export function parseUriList(text: string): ProfileItem[] {
  const out: ProfileItem[] = [];
  const lines: string[] = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const p: ProfileItem | null = parseUri(lines[i]);
    if (p !== null) out.push(p);
  }
  return out;
}

export function toUri(p: ProfileItem): string {
  if (p.configType === 'VMESS') return vmessToUri(p);
  if (p.configType === 'VLESS') {
    const pairs: Array<Array<string>> = queryPairs(p, true);
    pairs.push(['encryption', p.method.length > 0 ? p.method : 'none']);
    // encryption 应在前，但顺序不影响解析；重排：把 encryption 提前由解析兼容
    return buildUri('vless://', p.password, p, pairs);
  }
  if (p.configType === 'TROJAN') {
    return buildUri('trojan://', p.password, p, queryPairs(p, true));
  }
  if (p.configType === 'SHADOWSOCKS') {
    const userInfo: string = b64Encode(p.method + ':' + p.password, true);
    let qs: string = '';
    if (p.headerType === 'http' && p.host.length > 0) {
      qs = '?plugin=' + enc('obfs-local;obfs=http;obfs-host=' + p.host);
    }
    return 'ss://' + userInfo + '@' + ipv6Wrap(p.server) + ':' + p.serverPort + qs + '#' + enc(p.remarks);
  }
  if (p.configType === 'WIREGUARD') {
    const pairs: Array<Array<string>> = [];
    pairs.push(['publickey', p.publicKey]);
    if (p.reserved.length > 0) pairs.push(['reserved', p.reserved.replace(/\s/g, '')]);
    pairs.push(['address', p.localAddress.replace(/\s/g, '')]);
    if (p.mtu > 0) pairs.push(['mtu', String(p.mtu)]);
    if (p.preSharedKey.length > 0) pairs.push(['presharedkey', p.preSharedKey]);
    if (p.remoteDNS.length > 0) pairs.push(['dns', p.remoteDNS.replace(/\s/g, '')]);
    if (p.finalMask.length > 0) pairs.push(['fm', p.finalMask]);
    return buildUri('wireguard://', p.secretKey, p, pairs);
  }
  if (p.configType === 'HYSTERIA2') {
    const pairs: Array<Array<string>> = [];
    pairs.push(['security', p.security.length > 0 ? p.security : 'tls']);
    if (p.sni.length > 0) pairs.push(['sni', p.sni]);
    if (p.alpn.length > 0) pairs.push(['alpn', p.alpn]);
    pairs.push(['insecure', p.insecure ? '1' : '0']);
    if (p.obfsPassword.length > 0) {
      pairs.push(['obfs', 'salamander']);
      pairs.push(['obfs-password', p.obfsPassword]);
    }
    if (p.portHopping.length > 0) pairs.push(['mport', p.portHopping]);
    if (p.pinnedCA256.length > 0) pairs.push(['pinSHA256', p.pinnedCA256]);
    return buildUri('hysteria2://', p.password, p, pairs);
  }
  if (p.configType === 'SOCKS') {
    const ui: string = p.username.length > 0 ? p.username + ':' + p.password : '';
    if (ui.length === 0) {
      return 'socks://' + ipv6Wrap(p.server) + ':' + p.serverPort + '#' + enc(p.remarks);
    }
    return buildUri('socks://', ui, p, []);
  }
  if (p.configType === 'HTTP') {
    const scheme: string = p.security === 'tls' ? 'https://' : 'http://';
    const ui: string = p.username.length > 0 ? p.username + ':' + p.password : '';
    if (ui.length === 0) return scheme + ipv6Wrap(p.server) + ':' + p.serverPort + '#' + enc(p.remarks);
    return buildUri(scheme, ui, p, []);
  }
  if (p.configType === 'CUSTOM') return p.customConfig;
  return '';
}

/** 订阅/剪贴板内容：先整体 base64 尝试，再按行解析 */
export function parseSubscriptionText(text: string): ProfileItem[] {
  const t: string = text.trim();
  if (t.length === 0) return [];
  let plain: string = t;
  if (t.indexOf('://') < 0 && t.indexOf('[Interface]') < 0) {
    const dec: string = b64Decode(t.replace(/\s/g, ''));
    if (dec.indexOf('://') >= 0) plain = dec;
  }
  return parseUriList(plain);
}
