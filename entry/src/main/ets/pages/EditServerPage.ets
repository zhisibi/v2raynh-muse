// v2rayNG Harmony · 节点编辑页：按协议显隐关键字段，保存回 ServerStore
// 路由参数：id（空=新建）
import { router } from '@kit.ArkUI';
import { ServerStore, ServerEntry } from '../model/ServerStore';
import { ProfileItem, createProfile, ConfigType } from '../model/UriParser';
import { LogStore } from '../model/LogStore';
import { Pal } from '../components/Ui';

const TYPES: string[] = ['VMESS', 'VLESS', 'SHADOWSOCKS', 'TROJAN', 'WIREGUARD', 'HYSTERIA2', 'SOCKS', 'HTTP', 'CUSTOM'];
const NETS: string[] = ['tcp', 'ws', 'grpc', 'xhttp', 'httpupgrade', 'kcp', 'http', 'quic'];

@Entry
@Component
struct EditServerPage {
  @State editId: string = '';
  @State configType: string = 'VLESS';
  @State remarks: string = '';
  @State server: string = '';
  @State serverPort: string = '';
  @State password: string = '';
  @State method: string = '';
  @State flow: string = '';
  @State username: string = '';
  @State network: string = 'tcp';
  @State host: string = '';
  @State path: string = '';
  @State serviceName: string = '';
  @State security: string = '';
  @State sni: string = '';
  @State alpn: string = '';
  @State fingerPrint: string = '';
  @State insecure: boolean = false;
  @State publicKey: string = '';
  @State shortId: string = '';
  @State secretKey: string = '';
  @State preSharedKey: string = '';
  @State localAddress: string = '';
  @State reserved: string = '';
  @State mtu: string = '';
  @State remoteDNS: string = '';
  @State obfsPassword: string = '';
  @State portHopping: string = '';
  @State customConfig: string = '';
  @State msg: string = '';

  aboutToAppear(): void {
    const params: Record<string, Object> = router.getParams() as Record<string, Object>;
    const id: string = String(params['id'] ?? '');
    this.editId = id;
    if (id.length > 0) {
      const entry: ServerEntry | undefined = ServerStore.getById(id);
      if (entry !== undefined) {
        const p: ProfileItem = entry.profile;
        this.configType = p.configType;
        this.remarks = p.remarks;
        this.server = p.server;
        this.serverPort = p.serverPort;
        this.password = p.password;
        this.method = p.method;
        this.flow = p.flow;
        this.username = p.username;
        this.network = p.network;
        this.host = p.host;
        this.path = p.path;
        this.serviceName = p.serviceName;
        this.security = p.security;
        this.sni = p.sni;
        this.alpn = p.alpn;
        this.fingerPrint = p.fingerPrint;
        this.insecure = p.insecure;
        this.publicKey = p.publicKey;
        this.shortId = p.shortId;
        this.secretKey = p.secretKey;
        this.preSharedKey = p.preSharedKey;
        this.localAddress = p.localAddress;
        this.reserved = p.reserved;
        this.mtu = p.mtu > 0 ? String(p.mtu) : '';
        this.remoteDNS = p.remoteDNS;
        this.obfsPassword = p.obfsPassword;
        this.portHopping = p.portHopping;
        this.customConfig = p.customConfig;
      }
    }
  }

  isWg(): boolean {
    return this.configType === 'WIREGUARD';
  }

  isHy2(): boolean {
    return this.configType === 'HYSTERIA2';
  }

  isCustom(): boolean {
    return this.configType === 'CUSTOM';
  }

  needsStream(): boolean {
    return !this.isWg() && !this.isCustom() && this.configType !== 'SOCKS' && this.configType !== 'HTTP';
  }

  save(): void {
    if (!this.isCustom() && (this.server.trim().length === 0 || this.serverPort.trim().length === 0)) {
      this.msg = '请填写服务器地址与端口';
      return;
    }
    if (this.isCustom()) {
      try {
        JSON.parse(this.customConfig);
      } catch (e) {
        this.msg = '自定义配置不是合法 JSON';
        return;
      }
    }
    let base: ProfileItem = createProfile(this.configType as ConfigType);
    if (this.editId.length > 0) {
      const entry: ServerEntry | undefined = ServerStore.getById(this.editId);
      if (entry !== undefined) base = entry.profile;
    }
    base.configType = this.configType as ConfigType;
    base.remarks = this.remarks;
    base.server = this.server.trim();
    base.serverPort = this.serverPort.trim();
    base.password = this.password;
    base.method = this.method;
    base.flow = this.flow;
    base.username = this.username;
    base.network = this.isHy2() ? 'hysteria' : this.network;
    base.host = this.host;
    base.path = this.path;
    base.serviceName = this.serviceName;
    base.security = this.security;
    base.sni = this.sni;
    base.alpn = this.alpn;
    base.fingerPrint = this.fingerPrint;
    base.insecure = this.insecure;
    base.publicKey = this.publicKey;
    base.shortId = this.shortId;
    base.secretKey = this.secretKey;
    base.preSharedKey = this.preSharedKey;
    base.localAddress = this.localAddress;
    base.reserved = this.reserved;
    const mtuN: number = parseInt(this.mtu, 10);
    base.mtu = isNaN(mtuN) ? 0 : mtuN;
    base.remoteDNS = this.remoteDNS;
    base.obfsPassword = this.obfsPassword;
    base.portHopping = this.portHopping;
    base.customConfig = this.customConfig;
    if (this.editId.length > 0) {
      ServerStore.update(this.editId, base);
      LogStore.push('节点', '更新节点 ' + base.remarks);
    } else {
      ServerStore.add(base);
      LogStore.push('节点', '新增节点 ' + base.remarks);
    }
    router.back();
  }

  @Builder
  field(label: string, value: string, onInput: (v: string) => void, secret: boolean = false) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(Pal.sub)
        .width('100%')
      TextInput({ text: value })
        .height(42)
        .type(secret ? InputType.Password : InputType.Normal)
        .backgroundColor(Pal.chip)
        .borderRadius(9)
        .margin({ top: 4 })
        .onChange(onInput)
    }
    .width('100%')
    .margin({ top: 10 })
  }

  @Builder
  chipRow(label: string, options: string[], current: string, onPick: (v: string) => void) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(Pal.sub)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(options, (o: string) => {
          Text(o)
            .fontSize(12)
            .fontColor(current === o ? '#FFFFFF' : Pal.text)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(15)
            .backgroundColor(current === o ? Pal.accent : Pal.chip)
            .margin({ right: 6, top: 6 })
            .onClick(() => {
              onPick(o);
            })
        }, (o: string) => o)
      }
      .width('100%')
    }
    .width('100%')
    .margin({ top: 10 })
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(15)
          .fontColor(Pal.accent)
          .onClick(() => {
            router.back();
          })
        Text(this.editId.length > 0 ? '编辑节点' : '新建节点')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Pal.text)
          .margin({ left: 12 })
          .layoutWeight(1)
        Text('保存')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .padding({ left: 16, right: 16, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(Pal.accent)
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 10 })

      Scroll() {
        Column() {
          this.chipRow('协议', TYPES, this.configType, (v: string) => {
            this.configType = v;
          })
          this.field('备注', this.remarks, (v: string) => {
            this.remarks = v;
          })
          if (this.isCustom()) {
            Column() {
              Text('完整 Xray JSON 配置')
                .fontSize(12)
                .fontColor(Pal.sub)
                .width('100%')
              TextArea({ text: this.customConfig, placeholder: '{"inbounds":[...],"outbounds":[...]}' })
                .height(260)
                .backgroundColor(Pal.chip)
                .borderRadius(9)
                .margin({ top: 4 })
                .onChange((v: string) => {
                  this.customConfig = v;
                })
            }
            .width('100%')
            .margin({ top: 10 })
          } else {
            this.field('服务器地址', this.server, (v: string) => {
              this.server = v;
            })
            this.field('端口', this.serverPort, (v: string) => {
              this.serverPort = v;
            })
            if (this.isWg()) {
              this.field('私钥 (secretKey)', this.secretKey, (v: string) => {
                this.secretKey = v;
              }, true)
              this.field('对端公钥 (publicKey)', this.publicKey, (v: string) => {
                this.publicKey = v;
              })
              this.field('预共享密钥 (preSharedKey，可空)', this.preSharedKey, (v: string) => {
                this.preSharedKey = v;
              }, true)
              this.field('本地地址 (如 172.16.0.2/32)', this.localAddress, (v: string) => {
                this.localAddress = v;
              })
              this.field('reserved (如 0,0,0)', this.reserved, (v: string) => {
                this.reserved = v;
              })
              this.field('MTU', this.mtu, (v: string) => {
                this.mtu = v;
              })
              this.field('远程 DNS', this.remoteDNS, (v: string) => {
                this.remoteDNS = v;
              })
            } else if (this.isHy2()) {
              this.field('密码 (auth)', this.password, (v: string) => {
                this.password = v;
              }, true)
              this.field('混淆密码 obfs-password（salamander，可空）', this.obfsPassword, (v: string) => {
                this.obfsPassword = v;
              }, true)
              this.field('端口跳跃 mport（可空）', this.portHopping, (v: string) => {
                this.portHopping = v;
              })
              this.field('SNI', this.sni, (v: string) => {
                this.sni = v;
              })
            } else {
              if (this.configType === 'SOCKS' || this.configType === 'HTTP') {
                this.field('用户名（可空）', this.username, (v: string) => {
                  this.username = v;
                })
                this.field('密码（可空）', this.password, (v: string) => {
                  this.password = v;
                }, true)
              } else if (this.configType === 'SHADOWSOCKS') {
                this.field('加密方法 method', this.method, (v: string) => {
                  this.method = v;
                })
                this.field('密码', this.password, (v: string) => {
                  this.password = v;
                }, true)
              } else {
                this.field(this.configType === 'TROJAN' ? '密码' : 'UUID / 密码 (id)', this.password, (v: string) => {
                  this.password = v;
                }, true)
                if (this.configType === 'VMESS') {
                  this.field('加密 security（auto/aes-128-gcm…）', this.method, (v: string) => {
                    this.method = v;
                  })
                }
                if (this.configType === 'VLESS') {
                  this.field('encryption（默认 none）', this.method, (v: string) => {
                    this.method = v;
                  })
                  this.field('flow（如 xtls-rprx-vision，可空）', this.flow, (v: string) => {
                    this.flow = v;
                  })
                }
                if (this.configType === 'TROJAN') {
                  this.field('flow（可空）', this.flow, (v: string) => {
                    this.flow = v;
                  })
                }
              }
            }
            if (this.needsStream()) {
              this.chipRow('传输网络 network', NETS, this.network, (v: string) => {
                this.network = v;
              })
              this.field('Host', this.host, (v: string) => {
                this.host = v;
              })
              this.field('路径 Path / gRPC serviceName 见下', this.path, (v: string) => {
                this.path = v;
              })
              if (this.network === 'grpc') {
                this.field('serviceName', this.serviceName, (v: string) => {
                  this.serviceName = v;
                })
              }
              this.chipRow('安全 security', ['', 'tls', 'reality'], this.security, (v: string) => {
                this.security = v;
              })
              if (this.security === 'tls' || this.security === 'reality' || this.isHy2()) {
                this.field('SNI', this.sni, (v: string) => {
                  this.sni = v;
                })
                this.field('ALPN（如 h2,http/1.1）', this.alpn, (v: string) => {
                  this.alpn = v;
                })
                this.field('指纹 fingerprint', this.fingerPrint, (v: string) => {
                  this.fingerPrint = v;
                })
                Row() {
                  Text('允许不安全 allowInsecure')
                    .fontSize(14)
                    .fontColor(Pal.text)
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.insecure })
                    .onChange((on: boolean) => {
                      this.insecure = on;
                    })
                }
                .width('100%')
                .margin({ top: 10 })
              }
              if (this.security === 'reality') {
                this.field('REALITY publicKey (pbk)', this.publicKey, (v: string) => {
                  this.publicKey = v;
                })
                this.field('REALITY shortId (sid)', this.shortId, (v: string) => {
                  this.shortId = v;
                })
              }
            }
          }
          if (this.msg.length > 0) {
            Text(this.msg)
              .fontSize(12)
              .fontColor(Pal.bad)
              .width('100%')
              .margin({ top: 12 })
          }
          Button('保存')
            .width('100%')
            .height(46)
            .fontColor('#FFFFFF')
            .backgroundColor(Pal.accent)
            .borderRadius(12)
            .margin({ top: 16, bottom: 24 })
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Pal.bg)
  }
}
