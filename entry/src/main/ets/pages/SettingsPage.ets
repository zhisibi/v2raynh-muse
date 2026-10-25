// v2rayNG Harmony · 应用设置页（对齐安卓 SettingsActivity 分组）
// 核心设置 / VPN 设置 / 订阅设置 / 界面设置（主题+启动自动连接）/ 高级（geo 更新、核心版本）
import { router, promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SettingsStore } from '../model/SettingsStore';
import { AppSettings, ThemeMode } from '../model/XrayConfig';
import { coreVersion } from '../model/CoreBridge';
import { assetDirPath } from '../model/AssetInstaller';
import { Pal, fmtBytes } from '../components/Ui';

const GEOIP_URL: string =
  'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat';
const GEOSITE_URL: string =
  'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat';

async function downloadToFile(url: string, dest: string): Promise<number> {
  const req = http.createHttp();
  try {
    const resp: http.HttpResponse = await req.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 20000,
      readTimeout: 180000,
    });
    if (resp.responseCode !== 200) {
      throw new Error('HTTP ' + resp.responseCode);
    }
    const buf: ArrayBuffer = resp.result as ArrayBuffer;
    const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const SLICE: number = 4 * 1024 * 1024;
      let off: number = 0;
      while (off < buf.byteLength) {
        const end: number = Math.min(off + SLICE, buf.byteLength);
        fs.writeSync(file.fd, buf.slice(off, end), { offset: off });
        off = end;
      }
    } finally {
      fs.closeSync(file);
    }
    return buf.byteLength;
  } finally {
    req.destroy();
  }
}

function fileSizeText(path: string): string {
  try {
    const st = fs.statSync(path);
    return fmtBytes(st.size);
  } catch (e) {
    return '未释放';
  }
}

@Entry
@Component
struct SettingsPage {
  @State socksPort: string = '10808';
  @State httpPort: string = '10809';
  @State localDns: string = '223.5.5.5';
  @State remoteDns: string = '1.1.1.1';
  @State subHours: string = '24';
  @State logLevel: string = 'warning';
  @State enableUdp: boolean = true;
  @State sniffing: boolean = true;
  @State tun: boolean = true;
  @State ipv6: boolean = true;
  @State themeMode: ThemeMode = 'system';
  @State autoConnect: boolean = false;
  @State perAppMode: string = 'off';
  @State perAppList: string = '';
  @State msg: string = '';
  @State xrayVersion: string = '';
  @State geoBusy: boolean = false;
  @State geoMsg: string = '';
  @State geoSizes: string = '';

  aboutToAppear(): void {
    const s: AppSettings = SettingsStore.get();
    this.socksPort = String(s.socksPort);
    this.httpPort = String(s.httpPort);
    this.localDns = s.localDns;
    this.remoteDns = s.remoteDns;
    this.subHours = String(s.subUpdateHours);
    this.logLevel = s.logLevel;
    this.enableUdp = s.enableUdp;
    this.sniffing = s.sniffingEnabled;
    this.tun = s.tunEnabled;
    this.ipv6 = s.ipv6Enabled;
    this.themeMode = s.themeMode;
    this.autoConnect = s.autoConnect;
    this.perAppMode = s.perAppMode;
    this.perAppList = s.perAppList;
    this.xrayVersion = coreVersion();
    this.refreshGeoSizes();
  }

  private refreshGeoSizes(): void {
    const dir: string = assetDirPath();
    this.geoSizes = 'geoip.dat ' + fileSizeText(dir + '/geoip.dat') +
      ' · geosite.dat ' + fileSizeText(dir + '/geosite.dat');
  }

  private collect(): AppSettings {
    const s: AppSettings = SettingsStore.get();
    s.socksPort = Number(this.socksPort) || 10808;
    s.httpPort = Number(this.httpPort) || 10809;
    s.localDns = this.localDns.trim().length > 0 ? this.localDns.trim() : '223.5.5.5';
    s.remoteDns = this.remoteDns.trim().length > 0 ? this.remoteDns.trim() : '1.1.1.1';
    s.subUpdateHours = Number(this.subHours) || 24;
    s.logLevel = this.logLevel;
    s.enableUdp = this.enableUdp;
    s.sniffingEnabled = this.sniffing;
    s.tunEnabled = this.tun;
    s.ipv6Enabled = this.ipv6;
    s.themeMode = this.themeMode;
    s.autoConnect = this.autoConnect;
    s.perAppMode = (this.perAppMode === 'block' || this.perAppMode === 'allow') ? this.perAppMode : 'off';
    s.perAppList = this.perAppList;
    return s;
  }

  save(msgText: string = '设置已保存（重连后生效）'): void {
    SettingsStore.save(this.collect());
    this.msg = msgText;
    promptAction.showToast({ message: '设置已保存' });
  }

  async updateGeo(): Promise<void> {
    if (this.geoBusy) return;
    this.geoBusy = true;
    const dir: string = assetDirPath();
    try {
      this.geoMsg = '正在下载 geoip.dat…';
      const n1: number = await downloadToFile(GEOIP_URL, dir + '/geoip.dat');
      this.geoMsg = '正在下载 geosite.dat…';
      const n2: number = await downloadToFile(GEOSITE_URL, dir + '/geosite.dat');
      this.geoMsg = 'geo 数据已更新（geoip ' + fmtBytes(n1) + '、geosite ' + fmtBytes(n2) +
        '），断开重连后生效';
      promptAction.showToast({ message: 'geo 数据已更新' });
    } catch (e) {
      this.geoMsg = '更新失败：' + (e as Error).message + '（保留原有数据）';
    }
    this.geoBusy = false;
    this.refreshGeoSizes();
  }

  @Builder groupTitle(t: string) {
    Text(t).fontSize(13).fontWeight(FontWeight.Bold).fontColor(Pal.sub)
      .margin({ top: 16, bottom: 6 });
  }

  @Builder numRow(label: string, value: string, onChange: (v: string) => void) {
    Row() {
      Text(label).fontSize(14).fontColor(Pal.text).layoutWeight(1);
      TextInput({ text: value })
        .type(InputType.Number).height(38).width(110)
        .backgroundColor(Pal.card).borderRadius(8).textAlign(TextAlign.End)
        .onChange((v: string) => onChange(v))
        .onSubmit(() => this.save());
    }
    .width('100%').padding({ top: 6, bottom: 6 });
  }

  @Builder textRow(label: string, value: string, onChange: (v: string) => void) {
    Row() {
      Text(label).fontSize(14).fontColor(Pal.text).layoutWeight(1);
      TextInput({ text: value })
        .height(38).width(170)
        .backgroundColor(Pal.card).borderRadius(8).textAlign(TextAlign.End)
        .onChange((v: string) => onChange(v))
        .onSubmit(() => this.save());
    }
    .width('100%').padding({ top: 6, bottom: 6 });
  }

  @Builder switchRow(label: string, desc: string, on: boolean, onChange: (v: boolean) => void) {
    Row() {
      Column() {
        Text(label).fontSize(14).fontColor(Pal.text);
        if (desc.length > 0) {
          Text(desc).fontSize(11).fontColor(Pal.sub).margin({ top: 2 });
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(Pal.accent)
        .onChange((v: boolean) => onChange(v));
    }
    .width('100%').padding({ top: 6, bottom: 6 });
  }

  @Builder segBtn(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(selected ? '#FFFFFF' : Pal.text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(selected ? Pal.accent : Pal.chip)
      .onClick(() => onTap());
  }

  @Builder linkRow(label: string, desc: string, url: string) {
    Row() {
      Column() {
        Text(label).fontSize(14).fontColor(Pal.text);
        Text(desc).fontSize(11).fontColor(Pal.sub).margin({ top: 2 });
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      Text('›').fontSize(20).fontColor(Pal.sub);
    }
    .width('100%').padding({ top: 10, bottom: 10 })
    .onClick(() => {
      router.pushUrl({ url: url });
    });
  }

  build() {
    Column() {
      Row() {
        Text('‹').fontSize(26).fontColor(Pal.text).padding({ left: 4, right: 10 })
          .onClick(() => router.back());
        Text('应用设置').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Pal.text)
          .layoutWeight(1);
        Text('保存').fontSize(15).fontColor(Pal.accent)
          .onClick(() => this.save());
      }
      .width('100%').padding({ left: 10, right: 16, top: 12, bottom: 10 })
      .backgroundColor(Pal.card);

      Scroll() {
        Column() {
          // ---- 核心设置 ----
          this.groupTitle('核心设置');
          this.numRow('SOCKS 端口', this.socksPort, (v: string) => { this.socksPort = v; });
          this.numRow('HTTP 端口', this.httpPort, (v: string) => { this.httpPort = v; });
          Row() {
            Text('日志等级').fontSize(14).fontColor(Pal.text).layoutWeight(1);
            Row({ space: 6 }) {
              this.segBtn('warning', this.logLevel === 'warning', () => { this.logLevel = 'warning'; });
              this.segBtn('info', this.logLevel === 'info', () => { this.logLevel = 'info'; });
              this.segBtn('error', this.logLevel === 'error', () => { this.logLevel = 'error'; });
            }
          }
          .width('100%').padding({ top: 6, bottom: 6 });
          this.switchRow('流量嗅探', '识别 http/tls 域名用于规则分流', this.sniffing,
            (v: boolean) => { this.sniffing = v; });
          this.switchRow('UDP 转发', 'SOCKS/HTTP 入站的 UDP 支持', this.enableUdp,
            (v: boolean) => { this.enableUdp = v; });
          this.textRow('本地 DNS', this.localDns, (v: string) => { this.localDns = v; });
          this.textRow('远程 DNS', this.remoteDns, (v: string) => { this.remoteDns = v; });

          // ---- VPN 设置 ----
          this.groupTitle('VPN 设置');
          this.switchRow('TUN 模式', '经系统 VPN 接管全局流量（关则仅代理）', this.tun,
            (v: boolean) => { this.tun = v; });
          this.switchRow('IPv6 路由', 'TUN 下同时接管 IPv6 并防 DNS 泄漏', this.ipv6,
            (v: boolean) => { this.ipv6 = v; });
          Row() {
            Text('按应用代理').fontSize(14).fontColor(Pal.text).layoutWeight(1);
            Row({ space: 6 }) {
              this.segBtn('关闭', this.perAppMode === 'off', () => { this.perAppMode = 'off'; });
              this.segBtn('黑名单', this.perAppMode === 'block', () => { this.perAppMode = 'block'; });
              this.segBtn('仅名单', this.perAppMode === 'allow', () => { this.perAppMode = 'allow'; });
            }
          }
          .width('100%').padding({ top: 6, bottom: 6 });
          TextInput({ text: this.perAppList, placeholder: '包名逗号分隔，如 com.example.app,com.huawei.browser' })
            .height(40).backgroundColor(Pal.card).borderRadius(8)
            .onChange((v: string) => { this.perAppList = v; })
            .onSubmit(() => this.save());
          Text('基础版：依赖扩展侧包名过滤能力，名单外/内行为以真机为准。')
            .fontSize(11).fontColor(Pal.sub).margin({ top: 4 });

          // ---- 订阅设置 ----
          this.groupTitle('订阅设置');
          this.numRow('自动更新间隔（小时）', this.subHours, (v: string) => { this.subHours = v; });
          Text('应用回到前台时检查到期订阅并静默更新。')
            .fontSize(11).fontColor(Pal.sub);

          // ---- 界面设置 ----
          this.groupTitle('界面设置');
          Row() {
            Text('主题').fontSize(14).fontColor(Pal.text).layoutWeight(1);
            Row({ space: 6 }) {
              this.segBtn('跟随系统', this.themeMode === 'system', () => {
                this.themeMode = 'system';
                this.save('主题已保存');
                SettingsStore.applyColorMode(getContext(this));
              });
              this.segBtn('浅色', this.themeMode === 'light', () => {
                this.themeMode = 'light';
                this.save('主题已保存');
                SettingsStore.applyColorMode(getContext(this));
              });
              this.segBtn('深色', this.themeMode === 'dark', () => {
                this.themeMode = 'dark';
                this.save('主题已保存');
                SettingsStore.applyColorMode(getContext(this));
              });
            }
          }
          .width('100%').padding({ top: 6, bottom: 6 });
          Text('主题切换即时对本应用生效；若个别页面未刷新，重启应用即可。')
            .fontSize(11).fontColor(Pal.sub);
          this.switchRow('启动时自动连接', '打开应用后自动连接上次选中的节点', this.autoConnect,
            (v: boolean) => { this.autoConnect = v; });

          // ---- 高级 ----
          this.groupTitle('高级');
          Row() {
            Column() {
              Text('geo 数据更新').fontSize(14).fontColor(Pal.text);
              Text(this.geoSizes).fontSize(11).fontColor(Pal.sub).margin({ top: 2 });
              if (this.geoMsg.length > 0) {
                Text(this.geoMsg).fontSize(11).fontColor(Pal.accent).margin({ top: 2 });
              }
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start);
            Button(this.geoBusy ? '下载中…' : '更新').height(34).fontSize(13)
              .backgroundColor(Pal.accentSoft).fontColor(Pal.accent)
              .enabled(!this.geoBusy)
              .onClick(() => this.updateGeo());
          }
          .width('100%').padding({ top: 6, bottom: 6 });
          Row() {
            Text('Xray 核心版本').fontSize(14).fontColor(Pal.text).layoutWeight(1);
            Text(this.xrayVersion.length > 0 ? this.xrayVersion : '未知')
              .fontSize(13).fontColor(Pal.sub);
          }
          .width('100%').padding({ top: 6, bottom: 6 });
          this.linkRow('路由设置', '路由模式与自定义规则', 'pages/RoutingPage');
          this.linkRow('备份与恢复', '导出 / 导入全部数据', 'pages/BackupPage');
          this.linkRow('运行日志', '查看与导出日志', 'pages/LogsPage');
          this.linkRow('关于', '版本与说明', 'pages/AboutPage');

          if (this.msg.length > 0) {
            Text(this.msg).fontSize(12).fontColor(Pal.accent).margin({ top: 12 });
          }
          Text('v2rayNG Harmony 1.2.0 (104)').fontSize(11).fontColor(Pal.sub)
            .margin({ top: 14, bottom: 20 });
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 14, right: 14, bottom: 10 });
      }
      .layoutWeight(1).width('100%');
    }
    .width('100%').height('100%').backgroundColor(Pal.bg);
  }
}
