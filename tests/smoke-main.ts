// v2rayNG Harmony · 纯逻辑冒烟测试入口（UriParser + XrayConfig）
// 由 tests/run-smoke.sh 用 tsc strict 编译后在 Node 运行。
import {
  parseUri, toUri, parseSubscriptionText, ProfileItem, b64Encode,
} from '../entry/src/main/ets/model/UriParser';
import { buildXrayConfig, defaultSettings, AppSettings } from '../entry/src/main/ets/model/XrayConfig';

let passed: number = 0;
let failed: number = 0;

function assert(cond: boolean, name: string): void {
  if (cond) {
    passed++;
    console.log('PASS ' + name);
  } else {
    failed++;
    console.log('FAIL ' + name);
  }
}

function mustParse(uri: string, name: string): ProfileItem {
  const p: ProfileItem | null = parseUri(uri);
  assert(p !== null, name + ' 解析非空');
  if (p === null) throw new Error(name + ' parse failed');
  return p;
}

// ---- vmess base64 JSON ----
const vmessJson: string = JSON.stringify({
  v: '2', ps: 'VMess节点', add: 'vmess.example.com', port: '443',
  id: 'b831381d-6324-4d53-ad4f-8cda48b30811', aid: '0', scy: 'auto',
  net: 'ws', type: 'none', host: 'vmess.example.com', path: '/ws',
  tls: 'tls', sni: 'vmess.example.com', alpn: 'h2,http/1.1', fp: 'chrome', insecure: '0',
});
const vm: ProfileItem = mustParse('vmess://' + b64Encode(vmessJson), 'vmess-base64');
assert(vm.configType === 'VMESS', 'vmess 类型');
assert(vm.server === 'vmess.example.com' && vm.serverPort === '443', 'vmess 地址端口');
assert(vm.password === 'b831381d-6324-4d53-ad4f-8cda48b30811', 'vmess uuid');
assert(vm.network === 'ws' && vm.path === '/ws' && vm.security === 'tls', 'vmess 传输');
const vmRound: ProfileItem = mustParse(toUri(vm), 'vmess-roundtrip');
assert(vmRound.server === vm.server && vmRound.password === vm.password && vmRound.network === 'ws', 'vmess 往返一致');

// ---- vmess URL 式 ----
const vmStd: ProfileItem = mustParse(
  'vmess://b831381d-6324-4d53-ad4f-8cda48b30811@std.example.com:8443?encryption=auto&security=tls&type=ws&host=std.example.com&path=%2Fray#StdVMess',
  'vmess-std');
assert(vmStd.server === 'std.example.com' && vmStd.serverPort === '8443' && vmStd.network === 'ws', 'vmess-std 字段');

// ---- vless reality ----
const vl: ProfileItem = mustParse(
  'vless://b831381d-6324-4d53-ad4f-8cda48b30811@vless.example.com:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLICKEY123&sid=abcd&flow=xtls-rprx-vision&type=tcp&headerType=none#VLESS节点',
  'vless');
assert(vl.configType === 'VLESS' && vl.security === 'reality' && vl.publicKey === 'PUBLICKEY123', 'vless reality');
assert(vl.flow === 'xtls-rprx-vision' && vl.shortId === 'abcd', 'vless flow/sid');
const vlRound: ProfileItem = mustParse(toUri(vl), 'vless-roundtrip');
assert(vlRound.server === vl.server && vlRound.security === 'reality' && vlRound.flow === vl.flow, 'vless 往返一致');

// ---- ss SIP002（base64 userinfo） ----
const ssUser: string = b64Encode('aes-256-gcm:testpassword', true);
const ss: ProfileItem = mustParse('ss://' + ssUser + '@ss.example.com:8388#SS节点', 'ss-sip002');
assert(ss.configType === 'SHADOWSOCKS' && ss.method === 'aes-256-gcm' && ss.password === 'testpassword', 'ss sip002 方法密码');
assert(ss.server === 'ss.example.com' && ss.serverPort === '8388', 'ss 地址');
const ssRound: ProfileItem = mustParse(toUri(ss), 'ss-roundtrip');
assert(ssRound.method === ss.method && ssRound.password === ss.password && ssRound.server === ss.server, 'ss 往返一致');

// ---- ss legacy（整体 base64） ----
const ssLegacy: ProfileItem = mustParse(
  'ss://' + b64Encode('chacha20-ietf-poly1305:legacypass@legacy.example.com:1080') + '#Legacy',
  'ss-legacy');
assert(ssLegacy.method === 'chacha20-ietf-poly1305' && ssLegacy.password === 'legacypass' &&
  ssLegacy.server === 'legacy.example.com', 'ss legacy 字段');

// ---- ss 明文 userinfo ----
const ssPlain: ProfileItem = mustParse('ss://aes-128-gcm:plainpass@plain.example.com:10086#Plain', 'ss-plain');
assert(ssPlain.method === 'aes-128-gcm' && ssPlain.password === 'plainpass', 'ss 明文 userinfo');

// ---- trojan ----
const tj: ProfileItem = mustParse(
  'trojan://tjpassword@trojan.example.com:443?security=tls&sni=trojan.example.com&type=ws&host=trojan.example.com&path=%2Ftj#Trojan节点',
  'trojan');
assert(tj.configType === 'TROJAN' && tj.password === 'tjpassword' && tj.network === 'ws', 'trojan 字段');
const tjRound: ProfileItem = mustParse(toUri(tj), 'trojan-roundtrip');
assert(tjRound.password === tj.password && tjRound.server === tj.server, 'trojan 往返一致');

// ---- wireguard ----
const wg: ProfileItem = mustParse(
  'wireguard://AAABBBCCC1234567890abcdef%3D@wg.example.com:51820?publickey=PUBKEY456&reserved=0,0,0&address=172.16.0.2%2F32&mtu=1420&dns=1.1.1.1#WG节点',
  'wireguard');
assert(wg.configType === 'WIREGUARD' && wg.publicKey === 'PUBKEY456' && wg.localAddress === '172.16.0.2/32', 'wg 字段');
assert(wg.mtu === 1420 && wg.server === 'wg.example.com', 'wg mtu/地址');
const wgRound: ProfileItem = mustParse(toUri(wg), 'wg-roundtrip');
assert(wgRound.publicKey === wg.publicKey && wgRound.server === wg.server, 'wg 往返一致');

// ---- hysteria2 ----
const hy: ProfileItem = mustParse(
  'hysteria2://hypassword@hy.example.com:443?sni=hy.example.com&insecure=1&obfs=salamander&obfs-password=obfspass&mport=20000-30000#Hy2节点',
  'hy2');
assert(hy.configType === 'HYSTERIA2' && hy.password === 'hypassword' && hy.obfsPassword === 'obfspass', 'hy2 字段');
assert(hy.portHopping === '20000-30000' && hy.insecure === true, 'hy2 mport/insecure');
const hyRound: ProfileItem = mustParse(toUri(hy), 'hy2-roundtrip');
assert(hyRound.password === hy.password && hyRound.obfsPassword === 'obfspass', 'hy2 往返一致');
const hyAlias: ProfileItem = mustParse('hy2://p2@hy2.example.com:8443?sni=x#alias', 'hy2-alias');
assert(hyAlias.configType === 'HYSTERIA2' && hyAlias.serverPort === '8443', 'hy2 别名');

// ---- socks / http ----
const sk: ProfileItem = mustParse('socks://user1:pass1@socks.example.com:1080#Socks', 'socks');
assert(sk.configType === 'SOCKS' && sk.username === 'user1' && sk.password === 'pass1', 'socks 字段');
const hp: ProfileItem = mustParse('http://user2:pass2@http.example.com:8080#Http', 'http-proxy');
assert(hp.configType === 'HTTP' && hp.username === 'user2', 'http 代理字段');

// ---- 订阅文本（base64 整体） ----
const subBody: string = b64Encode(toUri(vl) + '\n' + toUri(ss) + '\n');
const subList: ProfileItem[] = parseSubscriptionText(subBody);
assert(subList.length === 2, '订阅 base64 解析 2 节点');

// ---- XrayConfig ----
const settings: AppSettings = defaultSettings();
const cfgText: string = buildXrayConfig(vl, settings);
const cfg: Record<string, Object> = JSON.parse(cfgText) as Record<string, Object>;
assert(cfg['outbounds'] !== undefined, 'xray 含 outbounds');
const outbounds: Array<Record<string, Object>> = cfg['outbounds'] as Object as Array<Record<string, Object>>;
const tags: string[] = outbounds.map((o: Record<string, Object>) => String(o['tag']));
assert(tags.indexOf('proxy') >= 0 && tags.indexOf('direct') >= 0 && tags.indexOf('block') >= 0, 'xray 含 proxy/direct/block');
const proxyOut: Record<string, Object> = outbounds[tags.indexOf('proxy')];
assert(String(proxyOut['protocol']) === 'vless', 'xray proxy 协议 vless');
const stream: Record<string, Object> = proxyOut['streamSettings'] as Object as Record<string, Object>;
assert(String(stream['security']) === 'reality' && stream['realitySettings'] !== undefined, 'xray reality 设置');
const inbounds: Array<Record<string, Object>> = cfg['inbounds'] as Object as Array<Record<string, Object>>;
let hasSocks: boolean = false;
let hasHttp: boolean = false;
for (let i = 0; i < inbounds.length; i++) {
  if (String(inbounds[i]['protocol']) === 'socks' && Number(inbounds[i]['port']) === 10808) hasSocks = true;
  if (String(inbounds[i]['protocol']) === 'http' && Number(inbounds[i]['port']) === 10809) hasHttp = true;
}
assert(hasSocks, 'xray socks inbound 10808');
assert(hasHttp, 'xray http inbound 10809');
const socksSet: Record<string, Object> =
  (inbounds[0]['settings'] as Object as Record<string, Object>);
assert(Boolean(socksSet['udp']) === true, 'xray socks udp 开');
assert(cfg['dns'] !== undefined && cfg['routing'] !== undefined && cfg['log'] !== undefined, 'xray 含 dns/routing/log');

// wireguard 配置
const wgCfg: Record<string, Object> = JSON.parse(buildXrayConfig(wg, settings)) as Record<string, Object>;
const wgOuts: Array<Record<string, Object>> = wgCfg['outbounds'] as Object as Array<Record<string, Object>>;
assert(String(wgOuts[0]['protocol']) === 'wireguard', 'xray wg outbound');
const wgSet: Record<string, Object> = wgOuts[0]['settings'] as Object as Record<string, Object>;
assert(String(wgSet['secretKey']).length > 0 && wgSet['peers'] !== undefined, 'xray wg settings');

// hysteria2 配置
const hyCfg: Record<string, Object> = JSON.parse(buildXrayConfig(hy, settings)) as Record<string, Object>;
const hyOuts: Array<Record<string, Object>> = hyCfg['outbounds'] as Object as Array<Record<string, Object>>;
assert(String(hyOuts[0]['protocol']) === 'hysteria', 'xray hy2 outbound 协议 hysteria');
const hyStream: Record<string, Object> = hyOuts[0]['streamSettings'] as Object as Record<string, Object>;
const hySet2: Record<string, Object> = hyStream['hysteriaSettings'] as Object as Record<string, Object>;
assert(Number(hySet2['version']) === 2, 'xray hy2 version=2');

// 全局模式
const gSettings: AppSettings = defaultSettings();
gSettings.routingMode = 'global';
const gCfg: Record<string, Object> = JSON.parse(buildXrayConfig(vl, gSettings)) as Record<string, Object>;
const gRouting: Record<string, Object> = gCfg['routing'] as Object as Record<string, Object>;
const gRules: Array<Record<string, Object>> = gRouting['rules'] as Object as Array<Record<string, Object>>;
assert(gRules.length >= 2, 'xray global 路由规则');

// CUSTOM 直通
const custom: ProfileItem = mustParse('{"inbounds":[],"outbounds":[]}', 'custom');
const customCfg: string = buildXrayConfig(custom, settings);
assert(customCfg.indexOf('"outbounds"') >= 0, 'custom 配置直通');

console.log('SMOKE RESULT: ' + passed + ' passed, ' + failed + ' failed');
if (failed > 0) {
  throw new Error('smoke failed: ' + failed);
}
