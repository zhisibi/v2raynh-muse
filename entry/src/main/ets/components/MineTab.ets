// v2rayNG Harmony · 我的：设置项 + 日志/关于入口 + 备份导出/导入
import { router } from '@kit.ArkUI';
import { SettingsStore } from '../model/SettingsStore';
import { AppSettings } from '../model/XrayConfig';
import { ServerStore } from '../model/ServerStore';
import { coreVersion } from '../model/CoreBridge';
import { parseSubscriptionText, ProfileItem, profileFromJson } from '../model/UriParser';
import { LogStore } from '../model/LogStore';
import { Pal, copyToClipboard, readClipboard } from './Ui';

@Component
export struct MineTab {
  @Prop @Watch('onTick') tick: number = 0;
  @State rev: number = 0;
  @State msg: string = '';
  @State socksPort: string = '10808';
  @State httpPort: string = '10809';
  @State remoteDns: string = '1.1.1.1';
  @State localDns: string = '223.5.5.5';
  @State subHours: string = '24';
  @State perAppMode: string = 'off';
  @State perAppList: string = '';

  onTick(): void {
    const s: AppSettings = SettingsStore.get();
    this.socksPort = String(s.socksPort);
    this.httpPort = String(s.httpPort);
    this.remoteDns = s.remoteDns;
    this.localDns = s.localDns;
    this.subHours = String(s.subUpdateHours);
    this.perAppMode = s.perAppMode;
    this.perAppList = s.perAppList;
    this.rev++;
  }

  setPerAppMode(m: string): void {
    this.perAppMode = m;
    const s: AppSettings = SettingsStore.get();
    s.perAppMode = (m === 'block' || m === 'allow') ? m : 'off';
    SettingsStore.save(s);
    this.rev++;
  }

  savePerAppList(): void {
    const s: AppSettings = SettingsStore.get();
    s.perAppList = this.perAppList.trim();
    SettingsStore.save(s);
    this.msg = '按应用代理名单已保存（重连后生效）';
    LogStore.push('设置', '按应用代理 mode=' + s.perAppMode + ' list=' + s.perAppList);
    this.rev++;
  }

  settings(): AppSettings {
    return SettingsStore.get();
  }

  savePorts(): void {
    const s: AppSettings = SettingsStore.get();
    const sp: number = parseInt(this.socksPort, 10);
    const hp: number = parseInt(this.httpPort, 10);
    if (!isNaN(sp) && sp > 0 && sp < 65536) s.socksPort = sp;
    if (!isNaN(hp) && hp > 0 && hp < 65536) s.httpPort = hp;
    s.remoteDns = this.remoteDns.trim().length > 0 ? this.remoteDns.trim() : '1.1.1.1';
    s.localDns = this.localDns.trim().length > 0 ? this.localDns.trim() : '223.5.5.5';
    const sh: number = parseInt(this.subHours, 10);
    s.subUpdateHours = isNaN(sh) ? 24 : sh;
    SettingsStore.save(s);
    this.msg = '设置已保存（重连后生效）';
    LogStore.push('设置', '保存端口/DNS/订阅间隔');
    this.rev++;
  }

  setBool(key: string, on: boolean): void {
    const s: AppSettings = SettingsStore.get();
    if (key === 'ipv6') s.ipv6Enabled = on;
    if (key === 'udp') s.enableUdp = on;
    if (key === 'sniff') s.sniffingEnabled = on;
    if (key === 'tun') s.tunEnabled = on;
    SettingsStore.save(s);
    LogStore.push('设置', key + '=' + on);
    this.rev++;
  }

  setMode(m: string): void {
    const s: AppSettings = SettingsStore.get();
    s.routingMode = m as 'rule' | 'global' | 'direct';
    SettingsStore.save(s);
    this.rev++;
  }

  async exportBackup(): Promise<void> {
    const ok: boolean = await copyToClipboard(ServerStore.exportJson());
    this.msg = ok ? '备份 JSON 已复制到剪贴板' : '复制失败';
  }

  async importBackup(): Promise<void> {
    const text: string = await readClipboard();
    if (text.trim().length === 0) {
      this.msg = '剪贴板为空';
      return;
    }
    let count: number = 0;
    try {
      const arr: Object[] = JSON.parse(text) as Object[];
      const profiles: ProfileItem[] = [];
      for (let i = 0; i < arr.length; i++) {
        const holder: Record<string, Object> = arr[i] as Object as Record<string, Object>;
        const profObj: Object | undefined = holder['profile'];
        if (profObj !== undefined) {
          profiles.push(profileFromJson(profObj as Object as Record<string, Object>));
        } else {
          profiles.push(profileFromJson(holder));
        }
      }
      count = ServerStore.addMany(profiles);
    } catch (e) {
      // 回退：按分享链接文本导入
      const profiles: ProfileItem[] = parseSubscriptionText(text);
      count = ServerStore.addMany(profiles);
    }
    this.msg = count > 0 ? ('已导入 ' + count + ' 个节点') : '导入失败：剪贴板内容无法识别';
    this.rev++;
  }

  @Builder
  toggleRow(label: string, desc: string, on: boolean, key: string) {
    Row() {
      Column() {
        Text(label)
          .fontSize(15)
          .fontColor(Pal.text)
        Text(desc)
          .fontSize(12)
          .fontColor(Pal.sub)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: on })
        .onChange((v: boolean) => {
          this.setBool(key, v);
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  inputRow(label: string, value: string, onInput: (v: string) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(Pal.text)
        .width(110)
      TextInput({ text: value })
        .height(40)
        .backgroundColor(Pal.chip)
        .borderRadius(8)
        .layoutWeight(1)
        .onChange(onInput)
    }
    .width('100%')
    .margin({ top: 8 })
  }

  build() {
    Scroll() {
      Column() {
        Text('设置')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Pal.text)
          .width('100%')

        Column() {
          this.toggleRow('TUN 模式', '开启=全局 VPN 隧道；关=仅本地 SOCKS/HTTP 代理', this.settings().tunEnabled, 'tun')
          Divider().color(Pal.line)
          this.toggleRow('IPv6', '内核与 TUN 启用 IPv6（防泄漏需双栈）', this.settings().ipv6Enabled, 'ipv6')
          Divider().color(Pal.line)
          this.toggleRow('UDP 转发', 'SOCKS 入站启用 UDP', this.settings().enableUdp, 'udp')
          Divider().color(Pal.line)
          this.toggleRow('流量嗅探', '嗅探 http/tls/quic 目标域名用于分流', this.settings().sniffingEnabled, 'sniff')
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 4 })
        .borderRadius(16)
        .backgroundColor(Pal.card)
        .margin({ top: 12 })

        Column() {
          Text('路由模式')
            .fontSize(14)
            .fontColor(Pal.text)
            .width('100%')
          Row({ space: 8 }) {
            Text('规则')
              .fontSize(13)
              .fontColor(this.settings().routingMode === 'rule' ? '#FFFFFF' : Pal.text)
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .borderRadius(17)
              .backgroundColor(this.settings().routingMode === 'rule' ? Pal.accent : Pal.chip)
              .onClick(() => {
                this.setMode('rule');
              })
            Text('全局')
              .fontSize(13)
              .fontColor(this.settings().routingMode === 'global' ? '#FFFFFF' : Pal.text)
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .borderRadius(17)
              .backgroundColor(this.settings().routingMode === 'global' ? Pal.accent : Pal.chip)
              .onClick(() => {
                this.setMode('global');
              })
            Text('直连')
              .fontSize(13)
              .fontColor(this.settings().routingMode === 'direct' ? '#FFFFFF' : Pal.text)
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .borderRadius(17)
              .backgroundColor(this.settings().routingMode === 'direct' ? Pal.accent : Pal.chip)
              .onClick(() => {
                this.setMode('direct');
              })
          }
          .margin({ top: 10 })
          this.inputRow('SOCKS 端口', this.socksPort, (v: string) => {
            this.socksPort = v;
          })
          this.inputRow('HTTP 端口', this.httpPort, (v: string) => {
            this.httpPort = v;
          })
          this.inputRow('远程 DNS', this.remoteDns, (v: string) => {
            this.remoteDns = v;
          })
          this.inputRow('本地 DNS', this.localDns, (v: string) => {
            this.localDns = v;
          })
          this.inputRow('订阅间隔(h)', this.subHours, (v: string) => {
            this.subHours = v;
          })
          Button('保存端口/DNS')
            .width('100%')
            .height(42)
            .fontColor('#FFFFFF')
            .backgroundColor(Pal.accent)
            .borderRadius(12)
            .margin({ top: 12 })
            .onClick(() => {
              this.savePorts();
            })
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(Pal.card)
        .margin({ top: 12 })

        Column() {
          Text('按应用代理')
            .fontSize(14)
            .fontColor(Pal.text)
            .width('100%')
          Text('黑名单=名单内应用不走 VPN；白名单=仅名单内应用走 VPN。填包名，逗号分隔。仅 TUN 模式生效')
            .fontSize(12)
            .fontColor(Pal.sub)
            .width('100%')
            .margin({ top: 4 })
          Row({ space: 8 }) {
            Text('关闭')
              .fontSize(13)
              .fontColor(this.perAppMode === 'off' ? '#FFFFFF' : Pal.text)
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .borderRadius(17)
              .backgroundColor(this.perAppMode === 'off' ? Pal.accent : Pal.chip)
              .onClick(() => {
                this.setPerAppMode('off');
              })
            Text('黑名单')
              .fontSize(13)
              .fontColor(this.perAppMode === 'block' ? '#FFFFFF' : Pal.text)
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .borderRadius(17)
              .backgroundColor(this.perAppMode === 'block' ? Pal.accent : Pal.chip)
              .onClick(() => {
                this.setPerAppMode('block');
              })
            Text('白名单')
              .fontSize(13)
              .fontColor(this.perAppMode === 'allow' ? '#FFFFFF' : Pal.text)
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
              .borderRadius(17)
              .backgroundColor(this.perAppMode === 'allow' ? Pal.accent : Pal.chip)
              .onClick(() => {
                this.setPerAppMode('allow');
              })
          }
          .margin({ top: 10 })
          TextInput({ placeholder: '包名,逗号分隔，如 com.microsoft.emmx', text: this.perAppList })
            .height(44)
            .backgroundColor(Pal.chip)
            .borderRadius(8)
            .width('100%')
            .margin({ top: 10 })
            .onChange((v: string) => {
              this.perAppList = v;
            })
          Button('保存名单')
            .width('100%')
            .height(42)
            .fontColor('#FFFFFF')
            .backgroundColor(Pal.accent)
            .borderRadius(12)
            .margin({ top: 10 })
            .onClick(() => {
              this.savePerAppList();
            })
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(Pal.card)
        .margin({ top: 12 })

        Column() {
          Row() {
            Text('运行日志')
              .fontSize(15)
              .fontColor(Pal.text)
              .layoutWeight(1)
            Text('查看 ›')
              .fontSize(13)
              .fontColor(Pal.accent)
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/LogsPage' }).catch(() => {
            });
          })
          Divider().color(Pal.line)
          Row() {
            Text('关于 v2rayNG')
              .fontSize(15)
              .fontColor(Pal.text)
              .layoutWeight(1)
            Text('1.1.0 · 内核 ' + (coreVersion().length > 0 ? coreVersion() : '未加载') + ' ›')
              .fontSize(12)
              .fontColor(Pal.sub)
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/AboutPage' }).catch(() => {
            });
          })
          Divider().color(Pal.line)
          Row({ space: 10 }) {
            Text('备份导出')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(15)
              .backgroundColor(Pal.accent)
              .onClick(() => {
                this.exportBackup();
              })
            Text('从剪贴板导入备份/链接')
              .fontSize(13)
              .fontColor(Pal.accent)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(15)
              .backgroundColor(Pal.accentSoft)
              .onClick(() => {
                this.importBackup();
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 10 })
        .borderRadius(16)
        .backgroundColor(Pal.card)
        .margin({ top: 12 })

        if (this.msg.length > 0) {
          Text(this.msg)
            .fontSize(12)
            .fontColor(Pal.accent)
            .width('100%')
            .margin({ top: 10 })
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}
