// v2rayNG Harmony · 首页：大连接按钮、状态、当前节点、流量、测速、模式切换
import { ConnectManager } from '../service/ConnectManager';
import { ServerStore, ServerEntry } from '../model/ServerStore';
import { SettingsStore } from '../model/SettingsStore';
import { queryTraffic, testDelay, isRunning } from '../model/CoreBridge';
import { buildXrayConfig } from '../model/XrayConfig';
import { LogStore } from '../model/LogStore';
import { Pal, fmtBytes, tcpPing } from './Ui';

@Component
export struct HomeTab {
  @Prop @Watch('onTick') tick: number = 0;
  @State status: string = 'stopped';
  @State busy: boolean = false;
  @State msg: string = '';
  @State selName: string = '';
  @State selAddr: string = '';
  @State nodeCount: number = 0;
  @State mode: string = 'rule';
  @State upTotal: number = 0;
  @State downTotal: number = 0;
  @State delay: number = -9; // -9 未测

  onTick(): void {
    this.status = ConnectManager.status();
    this.mode = SettingsStore.get().routingMode;
    this.nodeCount = ServerStore.count();
    const sel: ServerEntry | undefined = ServerStore.getSelected();
    this.selName = sel !== undefined ? sel.profile.remarks : '';
    this.selAddr = sel !== undefined ? (sel.profile.server + ':' + sel.profile.serverPort) : '';
    if (this.status === 'running') {
      try {
        const t: Record<string, number> = JSON.parse(queryTraffic()) as Record<string, number>;
        // 桥返回累计字节（upTotal/downTotal，与 up/down 同值）；速率由采样差分，页面只展示累计
        this.upTotal = Number(t['upTotal'] ?? t['up'] ?? 0);
        this.downTotal = Number(t['downTotal'] ?? t['down'] ?? 0);
      } catch (e) {
        // 忽略
      }
    }
  }

  async toggle(): Promise<void> {
    if (this.busy) return;
    this.msg = '';
    if (this.status === 'running') {
      ConnectManager.disconnect();
      this.status = ConnectManager.status();
      return;
    }
    this.busy = true;
    const err: string = await ConnectManager.connect();
    this.busy = false;
    this.status = ConnectManager.status();
    if (err.length > 0) this.msg = err;
  }

  async setMode(m: string): Promise<void> {
    if (m === this.mode || this.busy) return;
    const s = SettingsStore.get();
    s.routingMode = m as 'rule' | 'global' | 'direct';
    SettingsStore.save(s);
    this.mode = m;
    LogStore.push('设置', '路由模式切换为 ' + m);
    if (this.status === 'running') {
      this.busy = true;
      this.msg = '切换模式，正在重连…';
      ConnectManager.disconnect();
      const err: string = await ConnectManager.connect();
      this.busy = false;
      this.msg = err;
      this.status = ConnectManager.status();
    }
  }

  async doTest(): Promise<void> {
    const sel: ServerEntry | undefined = ServerStore.getSelected();
    if (sel === undefined) {
      this.msg = '请先选择节点';
      return;
    }
    this.msg = '测速中…';
    if (this.status === 'running' && isRunning()) {
      const cfg: string = buildXrayConfig(sel.profile, SettingsStore.get());
      const d: number = testDelay(cfg, 'http://www.gstatic.com/generate_204', 5000);
      this.delay = d;
      this.msg = d >= 0 ? ('延迟 ' + d + ' ms（经核心）') : '核心测速失败，回退 TCP 直连';
      if (d < 0) {
        const ms: number = await tcpPing(sel.profile.server, parseInt(sel.profile.serverPort, 10), 3000);
        this.delay = ms;
        this.msg = ms >= 0 ? ('TCP 直连延迟 ' + ms + ' ms') : '测速失败（不可达）';
      }
    } else {
      const ms: number = await tcpPing(sel.profile.server, parseInt(sel.profile.serverPort, 10), 3000);
      this.delay = ms;
      this.msg = ms >= 0 ? ('TCP 直连延迟 ' + ms + ' ms') : '测速失败（不可达）';
    }
    ServerStore.setDelay(sel.id, this.delay);
  }

  @Builder
  modeChip(m: string, label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.mode === m ? '#FFFFFF' : Pal.text)
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .borderRadius(17)
      .backgroundColor(this.mode === m ? Pal.accent : Pal.chip)
      .onClick(() => {
        this.setMode(m);
      })
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Text(this.status === 'running' ? '已连接' : (this.busy ? '连接中…' : '未连接'))
            .fontSize(15)
            .fontColor(this.status === 'running' ? Pal.good : Pal.sub)
          Text(this.selName.length > 0 ? this.selName : '还没有选择节点')
            .fontSize(21)
            .fontWeight(FontWeight.Medium)
            .fontColor(Pal.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
          Text(this.selAddr.length > 0 ? this.selAddr + ' · 共 ' + this.nodeCount + ' 个节点' : '共 ' + this.nodeCount + ' 个节点')
            .fontSize(12)
            .fontColor(Pal.sub)
            .margin({ top: 4 })
          Text('↑ ' + fmtBytes(this.upTotal) + '   ↓ ' + fmtBytes(this.downTotal) +
            (this.delay !== -9 ? '   ·   ' + (this.delay >= 0 ? this.delay + ' ms' : '超时') : ''))
            .fontSize(12)
            .fontColor(Pal.sub)
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .borderRadius(18)
        .backgroundColor(Pal.card)

        Button(this.busy ? '处理中…' : (this.status === 'running' ? '断开连接' : '连接'))
          .width('100%')
          .height(56)
          .fontSize(17)
          .fontColor('#FFFFFF')
          .backgroundColor(this.status === 'running' ? Pal.bad : Pal.accent)
          .borderRadius(16)
          .margin({ top: 14 })
          .onClick(() => {
            this.toggle();
          })

        Row({ space: 8 }) {
          this.modeChip('rule', '规则')
          this.modeChip('global', '全局')
          this.modeChip('direct', '直连')
          Blank()
          Text('测速')
            .fontSize(13)
            .fontColor(Pal.accent)
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .borderRadius(17)
            .backgroundColor(Pal.accentSoft)
            .onClick(() => {
              this.doTest();
            })
        }
        .width('100%')
        .margin({ top: 14 })

        if (this.msg.length > 0) {
          Text(this.msg)
            .fontSize(12)
            .fontColor(Pal.bad)
            .width('100%')
            .margin({ top: 12 })
        }

        Text('本地代理：SOCKS ' + SettingsStore.get().socksPort + ' / HTTP ' + SettingsStore.get().httpPort +
          (SettingsStore.get().tunEnabled ? ' · TUN 已开启' : ' · 仅代理模式（TUN 关）'))
          .fontSize(12)
          .fontColor(Pal.sub)
          .width('100%')
          .margin({ top: 16 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}
