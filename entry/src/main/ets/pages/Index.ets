// v2rayNG Harmony · 主界面（对齐安卓版 v2rayNG 单页形态）
// 顶栏（标题/搜索/扫码/菜单）+ 分组标签行 + 服务器列表 + 底部连接栏（连接键/选中节点/流量/测试）
import { router, promptAction } from '@kit.ArkUI';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { ServerStore, ServerEntry } from '../model/ServerStore';
import { Subscription, SubscriptionManager } from '../model/SubscriptionManager';
import { parseSubscriptionText, parseUriList, toUri } from '../model/UriParser';
import { ConnectManager } from '../service/ConnectManager';
import { SettingsStore } from '../model/SettingsStore';
import { buildXrayConfig } from '../model/XrayConfig';
import { isRunning, queryTraffic, testDelay } from '../model/CoreBridge';
import { LogStore } from '../model/LogStore';
import { Pal, copyToClipboard, fmtBytes, readClipboard, tcpPing } from '../components/Ui';

interface GroupTab {
  key: string;
  name: string;
}

type SortMode = 'time' | 'delay' | 'name';

/** 延迟排序权重：已测 < 未测(-1) < 超时(-2 及以下) */
function delayRank(d: number): number {
  if (d >= 0) return 0;
  if (d === -1) return 1;
  return 2;
}

function cmpEntries(a: ServerEntry, b: ServerEntry, mode: SortMode): number {
  if (mode === 'delay') {
    const ra: number = delayRank(a.delay);
    const rb: number = delayRank(b.delay);
    if (ra !== rb) return ra - rb;
    if (ra === 0 && a.delay !== b.delay) return a.delay - b.delay;
    return a.profile.addedTime - b.profile.addedTime;
  }
  if (mode === 'name') {
    const na: string = a.profile.remarks.toLowerCase();
    const nb: string = b.profile.remarks.toLowerCase();
    if (na < nb) return -1;
    if (na > nb) return 1;
    return a.profile.addedTime - b.profile.addedTime;
  }
  return a.profile.addedTime - b.profile.addedTime;
}

@Entry
@Component
struct Index {
  // 列表
  @State rev: number = 0;
  @State groupKey: string = 'all';
  @State sortMode: SortMode = 'time';
  @State showSearch: boolean = false;
  @State keyword: string = '';
  @State showImport: boolean = false;
  @State importText: string = '';
  @State testing: boolean = false;
  @State testProgress: string = '';
  private testCancel: boolean = false;
  // 连接状态
  @State status: string = 'idle';
  @State busy: boolean = false;
  @State selName: string = '';
  @State selProto: string = '';
  @State msg: string = '';
  @State upTotal: number = 0;
  @State downTotal: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.refreshSel();
    this.timer = setInterval(() => {
      this.tick();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  onPageShow(): void {
    this.rev++;
    this.refreshSel();
    this.tick();
  }

  private tick(): void {
    this.status = ConnectManager.status();
    this.refreshSel();
    if (this.status === 'running') {
      const raw: string = queryTraffic();
      if (raw.length > 0) {
        try {
          const o: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
          this.upTotal = Number(o['upTotal'] ?? 0);
          this.downTotal = Number(o['downTotal'] ?? 0);
        } catch (e) {
          // 忽略单帧解析失败
        }
      }
    }
  }

  private refreshSel(): void {
    const sel = ServerStore.getSelected();
    if (sel !== undefined) {
      this.selName = sel.profile.remarks;
      this.selProto = sel.profile.configType + ' · ' + sel.profile.server + ':' + sel.profile.serverPort;
    } else {
      this.selName = '';
      this.selProto = '';
    }
  }

  // ---------- 分组与过滤 ----------
  private groups(): GroupTab[] {
    void this.rev;
    const tabs: GroupTab[] = [{ key: 'all', name: '全部' }];
    const subs: Subscription[] = SubscriptionManager.getAll();
    for (let i = 0; i < subs.length; i++) {
      const t: GroupTab = { key: subs[i].id, name: subs[i].name };
      tabs.push(t);
    }
    const all: ServerEntry[] = ServerStore.getEntries();
    let hasManual: boolean = false;
    for (let i = 0; i < all.length; i++) {
      if (all[i].profile.subscriptionId.length === 0) {
        hasManual = true;
        break;
      }
    }
    if (hasManual) {
      const t: GroupTab = { key: 'none', name: '未分组' };
      tabs.push(t);
    }
    return tabs;
  }

  private visible(): ServerEntry[] {
    void this.rev;
    let list: ServerEntry[] = ServerStore.getEntries();
    if (this.groupKey === 'none') {
      list = list.filter((e: ServerEntry) => e.profile.subscriptionId.length === 0);
    } else if (this.groupKey !== 'all') {
      const key: string = this.groupKey;
      list = list.filter((e: ServerEntry) => e.profile.subscriptionId === key);
    }
    const kw: string = this.keyword.trim().toLowerCase();
    if (kw.length > 0) {
      list = list.filter((e: ServerEntry) =>
        e.profile.remarks.toLowerCase().indexOf(kw) >= 0 ||
        e.profile.server.toLowerCase().indexOf(kw) >= 0);
    }
    const mode: SortMode = this.sortMode;
    list.sort((a: ServerEntry, b: ServerEntry) => cmpEntries(a, b, mode));
    return list;
  }

  private delayText(d: number): string {
    if (d === -1) return '-';
    if (d <= -2) return '超时';
    return d + ' ms';
  }

  private delayColor(d: number): string {
    if (d === -1) return Pal.sub;
    if (d <= -2) return Pal.bad;
    if (d < 150) return Pal.good;
    if (d < 400) return Pal.warn;
    return Pal.bad;
  }

  // ---------- 连接 ----------
  private statusLabel(): string {
    if (this.status === 'running') return '已连接';
    if (this.status === 'starting') return '连接中…';
    if (this.status === 'error') return '连接失败（看日志）';
    return '未连接';
  }

  async toggle(): Promise<void> {
    if (this.busy) return;
    if (this.status === 'running' || this.status === 'starting') {
      ConnectManager.disconnect();
      this.status = 'idle';
      this.msg = '已断开';
      return;
    }
    const sel = ServerStore.getSelected();
    if (sel === undefined) {
      this.msg = '请先在列表中选择一个节点';
      return;
    }
    this.busy = true;
    this.msg = SettingsStore.get().tunEnabled ? '正在连接（TUN）…' : '正在连接（仅代理）…';
    const err: string = await ConnectManager.connect();
    this.busy = false;
    this.status = ConnectManager.status();
    this.msg = err.length > 0 ? '连接失败：' + err : '已连接 ' + sel.profile.remarks;
    if (err.length === 0) {
      promptAction.showToast({ message: '已连接' });
    }
  }

  /** 底部「测试」：对运行实例做真实延迟测试，未运行则测选中节点端口连通性 */
  async doTest(): Promise<void> {
    const sel = ServerStore.getSelected();
    if (sel === undefined) {
      this.msg = '请先选择节点';
      return;
    }
    if (this.status === 'running' && isRunning()) {
      const s = SettingsStore.get();
      const cfg: string = buildXrayConfig(sel.profile, s);
      const ms: number = testDelay(cfg, 'http://www.gstatic.com/generate_204', 10000);
      if (ms >= 0) {
        this.msg = '代理延迟 ' + ms + ' ms（真实出站测试）';
        promptAction.showToast({ message: '延迟 ' + ms + ' ms' });
        return;
      }
    }
    const port: number = Number(sel.profile.serverPort);
    if (isNaN(port) || port <= 0) {
      this.msg = '该节点无可用端口可测';
      return;
    }
    this.msg = '正在测速 ' + sel.profile.remarks + '…';
    const ms: number = await tcpPing(sel.profile.server, port, 3000);
    if (ms >= 0) {
      this.msg = 'TCP 延迟 ' + ms + ' ms（未连接核心时的端口连通性）';
      ServerStore.setDelay(sel.id, ms);
    } else {
      this.msg = '测速超时（端口不可达或核心未运行）';
      ServerStore.setDelay(sel.id, -2);
    }
    this.rev++;
  }

  // ---------- 列表操作 ----------
  private pick(e: ServerEntry): void {
    ServerStore.setSelected(e.id);
    this.refreshSel();
    this.rev++;
    this.msg = '已选择 ' + e.profile.remarks;
  }

  async testOne(e: ServerEntry): Promise<void> {
    if (isRunning()) {
      const s = SettingsStore.get();
      const cfg: string = buildXrayConfig(e.profile, s);
      const ms: number = testDelay(cfg, 'http://www.gstatic.com/generate_204', 10000);
      if (ms >= 0) {
        ServerStore.setDelay(e.id, ms);
        this.msg = e.profile.remarks + ' 真实延迟 ' + ms + ' ms';
        this.rev++;
        return;
      }
    }
    const port: number = Number(e.profile.serverPort);
    if (isNaN(port) || port <= 0) {
      this.msg = '该节点无可用端口（CUSTOM）';
      return;
    }
    const ms: number = await tcpPing(e.profile.server, port, 3000);
    if (ms >= 0) {
      ServerStore.setDelay(e.id, ms);
      this.msg = e.profile.remarks + ' TCP 延迟 ' + ms + ' ms';
    } else {
      ServerStore.setDelay(e.id, -2);
      this.msg = e.profile.remarks + ' 测速超时';
    }
    this.rev++;
  }

  async testAll(): Promise<void> {
    if (this.testing) {
      this.testCancel = true;
      return;
    }
    const list: ServerEntry[] = this.visible();
    if (list.length === 0) {
      this.msg = '当前分组没有节点';
      return;
    }
    const viaCore: boolean = isRunning();
    this.testing = true;
    this.testCancel = false;
    let okCount: number = 0;
    for (let i = 0; i < list.length; i++) {
      if (this.testCancel) {
        this.testProgress = '测速已取消（' + i + '/' + list.length + '）';
        break;
      }
      const e: ServerEntry = list[i];
      this.testProgress = '测速中 ' + (i + 1) + '/' + list.length + '：' + e.profile.remarks;
      let ms: number = -2;
      if (viaCore) {
        const s = SettingsStore.get();
        const cfg: string = buildXrayConfig(e.profile, s);
        ms = testDelay(cfg, 'http://www.gstatic.com/generate_204', 10000);
      } else {
        const port: number = Number(e.profile.serverPort);
        if (!isNaN(port) && port > 0) {
          ms = await tcpPing(e.profile.server, port, 3000);
        }
      }
      ServerStore.setDelay(e.id, ms);
      if (ms >= 0) okCount++;
      this.rev++;
    }
    this.testing = false;
    if (!this.testCancel) {
      this.testProgress = '';
      this.msg = '全部测速完成：' + okCount + '/' + list.length + ' 可达' +
        (viaCore ? '（核心真实延迟）' : '（TCP 端口连通性）');
    }
  }

  private confirmDelete(e: ServerEntry): void {
    AlertDialog.show({
      title: '删除节点',
      message: '确定删除「' + e.profile.remarks + '」？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#C0392B',
        action: () => {
          ServerStore.remove(e.id);
          this.msg = '已删除 ' + e.profile.remarks;
          this.refreshSel();
          this.rev++;
        },
      },
    });
  }

  // ---------- 导入 ----------
  private addImported(text: string): number {
    let count: number = 0;
    const subList = parseSubscriptionText(text);
    if (subList.length > 0) {
      ServerStore.addMany(subList);
      count = subList.length;
    } else {
      const list = parseUriList(text);
      for (let i = 0; i < list.length; i++) {
        ServerStore.add(list[i]);
      }
      count = list.length;
    }
    if (count > 0) {
      LogStore.push('导入', '导入 ' + count + ' 个节点');
      this.groupKey = 'all';
    }
    return count;
  }

  async importFromClipboard(): Promise<void> {
    const text: string = await readClipboard();
    if (text.trim().length === 0) {
      this.msg = '剪贴板为空（需先在系统里复制节点链接或订阅内容）';
      return;
    }
    const n: number = this.addImported(text);
    this.msg = n > 0 ? '已从剪贴板导入 ' + n + ' 个节点' : '剪贴板内容里没找到可导入的节点';
    this.rev++;
  }

  private pasteImport(): void {
    const n: number = this.addImported(this.importText);
    if (n > 0) {
      this.importText = '';
      this.showImport = false;
      this.msg = '已导入 ' + n + ' 个节点';
    } else {
      this.msg = '没有解析到节点：请粘贴 vmess/vless/ss/trojan 等链接或订阅内容';
    }
    this.rev++;
  }

  async scanImport(): Promise<void> {
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: true,
        enableAlbum: true,
      };
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(getContext(this), options);
      const text: string = result.originalValue;
      if (text.length === 0) {
        this.msg = '扫码未识别到内容';
        return;
      }
      const n: number = this.addImported(text);
      this.msg = n > 0 ? '扫码导入 ' + n + ' 个节点' : '二维码内容不是可导入的节点';
      this.rev++;
    } catch (e) {
      this.msg = '扫码取消或失败（需相机权限）';
    }
  }

  // ---------- 菜单 ----------
  @Builder topMenu() {
    Menu() {
      MenuItem({ content: '从剪贴板导入' })
        .onClick(() => { this.importFromClipboard(); });
      MenuItem({ content: '粘贴导入' })
        .onClick(() => { this.showImport = !this.showImport; });
      MenuItem({ content: '手动添加' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/EditServerPage', params: { id: '' } });
        });
      MenuItem({ content: '全部测速' })
        .onClick(() => { this.testAll(); });
      MenuItem({ content: '订阅管理' })
        .onClick(() => { router.pushUrl({ url: 'pages/SubscriptionsPage' }); });
      MenuItem({ content: '路由设置' })
        .onClick(() => { router.pushUrl({ url: 'pages/RoutingPage' }); });
      MenuItem({ content: '应用设置' })
        .onClick(() => { router.pushUrl({ url: 'pages/SettingsPage' }); });
      MenuItem({ content: '备份与恢复' })
        .onClick(() => { router.pushUrl({ url: 'pages/BackupPage' }); });
      MenuItem({ content: '日志' })
        .onClick(() => { router.pushUrl({ url: 'pages/LogsPage' }); });
      MenuItem({ content: '关于' })
        .onClick(() => { router.pushUrl({ url: 'pages/AboutPage' }); });
    }
  }

  @Builder sortMenu() {
    Menu() {
      MenuItem({ content: '按添加时间' })
        .onClick(() => { this.sortMode = 'time'; });
      MenuItem({ content: '按延迟' })
        .onClick(() => { this.sortMode = 'delay'; });
      MenuItem({ content: '按名称' })
        .onClick(() => { this.sortMode = 'name'; });
    }
  }

  @Builder rowMenu(e: ServerEntry) {
    Menu() {
      MenuItem({ content: '测速' })
        .onClick(() => { this.testOne(e); });
      MenuItem({ content: '编辑' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/EditServerPage', params: { id: e.id } });
        });
      MenuItem({ content: '分享链接' })
        .onClick(() => {
          copyToClipboard(toUri(e.profile));
          this.msg = '分享链接已复制';
          promptAction.showToast({ message: '链接已复制' });
        });
      MenuItem({ content: '分享二维码' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/QrSharePage', params: { id: e.id } });
        });
      MenuItem({ content: '复制地址' })
        .onClick(() => {
          copyToClipboard(e.profile.server + ':' + e.profile.serverPort);
          this.msg = '地址已复制';
        });
      MenuItem({ content: '删除' })
        .onClick(() => { this.confirmDelete(e); });
    }
  }

  @Builder entryRow(e: ServerEntry) {
    Row() {
      Text(ServerStore.getSelectedId() === e.id ? '●' : '○')
        .fontSize(13)
        .fontColor(ServerStore.getSelectedId() === e.id ? Pal.accent : Pal.sub)
        .margin({ right: 8 });
      Column() {
        Text(e.profile.remarks).fontSize(15).fontColor(Pal.text).maxLines(1);
        Text(e.profile.configType + ' · ' + e.profile.server + ':' + e.profile.serverPort)
          .fontSize(12).fontColor(Pal.sub).maxLines(1).margin({ top: 2 });
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start);
      Text(this.delayText(e.delay))
        .fontSize(13).fontColor(this.delayColor(e.delay))
        .margin({ right: 6 });
      Text('⋮').fontSize(18).fontColor(Pal.sub)
        .padding({ left: 8, right: 2, top: 6, bottom: 6 })
        .bindMenu(this.rowMenu(e));
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(ServerStore.getSelectedId() === e.id ? Pal.accentSoft : Pal.card)
    .margin({ bottom: 8 })
    .onClick(() => this.pick(e))
    .bindContextMenu(this.rowMenu(e), ResponseType.LongPress);
  }

  build() {
    Column() {
      // ---- 顶栏 ----
      Row() {
        Text('v2rayNG').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Pal.text)
          .layoutWeight(1);
        Text('🔍').fontSize(18).padding(8)
          .onClick(() => { this.showSearch = !this.showSearch; });
        Text('📷').fontSize(18).padding(8)
          .onClick(() => { this.scanImport(); });
        Text('⋮').fontSize(20).fontColor(Pal.text).padding(8)
          .bindMenu(this.topMenu());
      }
      .width('100%').padding({ left: 14, right: 8, top: 12, bottom: 8 })
      .backgroundColor(Pal.card);

      if (this.showSearch) {
        TextInput({ text: this.keyword, placeholder: '搜索备注或地址（当前分组）' })
          .height(40).margin({ left: 12, right: 12, top: 8 })
          .backgroundColor(Pal.card).borderRadius(8)
          .onChange((v: string) => { this.keyword = v; });
      }

      if (this.showImport) {
        Column() {
          TextArea({ text: this.importText, placeholder: '粘贴节点链接（每行一条）或整份订阅内容' })
            .height(90).backgroundColor(Pal.card).borderRadius(8)
            .onChange((v: string) => { this.importText = v; });
          Row({ space: 10 }) {
            Button('导入').height(36).fontSize(13)
              .backgroundColor(Pal.accent).fontColor('#FFFFFF')
              .onClick(() => this.pasteImport());
            Button('从剪贴板导入').height(36).fontSize(13)
              .backgroundColor(Pal.chip).fontColor(Pal.text)
              .onClick(() => { this.importFromClipboard(); });
            Button('关闭').height(36).fontSize(13)
              .backgroundColor(Pal.chip).fontColor(Pal.text)
              .onClick(() => { this.showImport = false; });
          }
          .margin({ top: 8 });
        }
        .width('100%').padding({ left: 12, right: 12, top: 8 });
      }

      // ---- 分组标签行 + 排序 ----
      Row() {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.groups(), (g: GroupTab) => {
              Text(g.name)
                .fontSize(13)
                .fontColor(this.groupKey === g.key ? '#FFFFFF' : Pal.text)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(15)
                .backgroundColor(this.groupKey === g.key ? Pal.accent : Pal.chip)
                .onClick(() => { this.groupKey = g.key; });
            }, (g: GroupTab) => g.key);
          }
          .padding({ left: 12, right: 4, top: 8, bottom: 8 });
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1);
        Text('排序 ▾').fontSize(13).fontColor(Pal.accent)
          .padding({ left: 6, right: 12, top: 8, bottom: 8 })
          .bindMenu(this.sortMenu());
      }
      .width('100%');

      if (this.testProgress.length > 0) {
        Row() {
          Text(this.testProgress).fontSize(12).fontColor(Pal.accent).layoutWeight(1);
          if (this.testing) {
            Text('取消').fontSize(12).fontColor(Pal.bad)
              .onClick(() => { this.testCancel = true; });
          }
        }
        .width('100%').padding({ left: 14, right: 14, top: 2, bottom: 2 });
      }
      if (this.msg.length > 0) {
        Text(this.msg).fontSize(12).fontColor(Pal.sub)
          .width('100%').padding({ left: 14, right: 14, top: 2, bottom: 2 });
      }

      // ---- 服务器列表 ----
      Scroll() {
        Column() {
          if (this.visible().length === 0) {
            Text('当前分组没有节点。\n点右上角 ⋮ 从剪贴板导入、粘贴导入或手动添加；也可以先去「订阅管理」添加订阅。')
              .fontSize(13).fontColor(Pal.sub)
              .padding({ top: 28, left: 8, right: 8 });
          }
          ForEach(this.visible(), (e: ServerEntry) => {
            this.entryRow(e);
          }, (e: ServerEntry) => e.id);
        }
        .width('100%').padding({ left: 12, right: 12, top: 6, bottom: 10 });
      }
      .layoutWeight(1).width('100%');

      // ---- 底部连接栏 ----
      Row() {
        Text(this.status === 'running' ? '⏻' : '⏵')
          .fontSize(22).fontColor('#FFFFFF')
          .width(52).height(52).textAlign(TextAlign.Center)
          .borderRadius(26)
          .backgroundColor(this.status === 'running' ? Pal.bad : Pal.accent)
          .opacity(this.busy ? 0.5 : 1)
          .onClick(() => { this.toggle(); });
        Column() {
          Text(this.selName.length > 0 ? this.selName : '未选择节点')
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(Pal.text).maxLines(1);
          Text(this.selProto.length > 0 ? this.selProto : this.statusLabel())
            .fontSize(11).fontColor(Pal.sub).maxLines(1).margin({ top: 2 });
          if (this.status === 'running') {
            Text('↑ ' + fmtBytes(this.upTotal) + '  ↓ ' + fmtBytes(this.downTotal))
              .fontSize(11).fontColor(Pal.sub).margin({ top: 2 });
          }
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        .margin({ left: 10, right: 8 });
        Column() {
          Text(this.statusLabel())
            .fontSize(12)
            .fontColor(this.status === 'running' ? Pal.good : Pal.sub);
          Button('测试').height(30).fontSize(12)
            .backgroundColor(Pal.accentSoft).fontColor(Pal.accent)
            .margin({ top: 4 })
            .onClick(() => { this.doTest(); });
        }
        .alignItems(HorizontalAlign.End);
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 12 })
      .backgroundColor(Pal.card);
    }
    .width('100%').height('100%').backgroundColor(Pal.bg);
  }
}
