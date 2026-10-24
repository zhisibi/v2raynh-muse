// v2rayNG Harmony · 节点页：按订阅分组、选中/删除/编辑、导入、手动添加、测速
import { router } from '@kit.ArkUI';
import { ServerStore, ServerEntry } from '../model/ServerStore';
import { SubscriptionManager, Subscription } from '../model/SubscriptionManager';
import { parseUriList, parseSubscriptionText, ProfileItem, toUri } from '../model/UriParser';
import { ConnectManager } from '../service/ConnectManager';
import { LogStore } from '../model/LogStore';
import { Pal, tcpPing, readClipboard, copyToClipboard } from './Ui';

@Component
export struct ServersTab {
  @Prop @Watch('onTick') tick: number = 0;
  @State rev: number = 0;
  @State hint: string = '';
  @State showImport: boolean = false;
  @State importText: string = '';
  @State testing: boolean = false;

  onTick(): void {
    this.rev++;
  }

  entries(): ServerEntry[] {
    return ServerStore.getEntries();
  }

  groupName(e: ServerEntry): string {
    if (e.profile.subscriptionId.length === 0) return '手动添加';
    const subs: Subscription[] = SubscriptionManager.getAll();
    for (let i = 0; i < subs.length; i++) {
      if (subs[i].id === e.profile.subscriptionId) return subs[i].name;
    }
    return '订阅';
  }

  groups(): string[] {
    const out: string[] = [];
    const es: ServerEntry[] = this.entries();
    for (let i = 0; i < es.length; i++) {
      const g: string = this.groupName(es[i]);
      if (out.indexOf(g) < 0) out.push(g);
    }
    return out;
  }

  entriesOf(group: string): ServerEntry[] {
    return this.entries().filter((e: ServerEntry) => this.groupName(e) === group);
  }

  pick(e: ServerEntry): void {
    ServerStore.setSelected(e.id);
    this.hint = '已选中 ' + e.profile.remarks;
    if (ConnectManager.status() === 'running') {
      this.hint += '（重连后生效）';
    }
    this.rev++;
  }

  async testOne(e: ServerEntry): Promise<void> {
    const ms: number = await tcpPing(e.profile.server, parseInt(e.profile.serverPort, 10), 3000);
    ServerStore.setDelay(e.id, ms >= 0 ? ms : -2);
  }

  async testAll(): Promise<void> {
    if (this.testing) return;
    this.testing = true;
    this.hint = '测速中（TCP 直连，仅供参考）…';
    const list: ServerEntry[] = this.entries();
    for (let i = 0; i < list.length; i++) {
      await this.testOne(list[i]);
      this.rev++;
    }
    this.testing = false;
    this.hint = '测速完成';
  }

  delayText(e: ServerEntry): string {
    if (e.delay === -1) return '未测';
    if (e.delay < 0) return '超时';
    return e.delay + ' ms';
  }

  async importFromClipboard(): Promise<void> {
    const text: string = await readClipboard();
    if (text.trim().length === 0) {
      this.hint = '剪贴板为空';
      return;
    }
    const profiles: ProfileItem[] = parseSubscriptionText(text);
    if (profiles.length === 0) {
      this.hint = '剪贴板内容未解析出节点';
      return;
    }
    ServerStore.addMany(profiles);
    LogStore.push('导入', '剪贴板导入 ' + profiles.length + ' 个节点');
    this.hint = '已导入 ' + profiles.length + ' 个节点';
    this.rev++;
  }

  doImportText(): void {
    const profiles: ProfileItem[] = parseUriList(this.importText);
    if (profiles.length === 0) {
      this.hint = '未解析出节点，请检查链接';
      return;
    }
    ServerStore.addMany(profiles);
    this.hint = '已导入 ' + profiles.length + ' 个节点';
    this.importText = '';
    this.showImport = false;
    this.rev++;
  }

  async shareEntry(e: ServerEntry): Promise<void> {
    const uri: string = toUri(e.profile);
    const ok: boolean = await copyToClipboard(uri);
    this.hint = ok ? '分享链接已复制' : '复制失败';
  }

  editEntry(e: ServerEntry): void {
    const params: Record<string, string> = { 'id': e.id };
    router.pushUrl({ url: 'pages/EditServerPage', params: params }).catch(() => {
      this.hint = '打开编辑页失败';
    });
  }

  newEntry(): void {
    const params: Record<string, string> = { 'id': '' };
    router.pushUrl({ url: 'pages/EditServerPage', params: params }).catch(() => {
      this.hint = '打开编辑页失败';
    });
  }

  @Builder
  entryRow(e: ServerEntry) {
    Column() {
      Row() {
        Column() {
          Row() {
            if (ServerStore.getSelectedId() === e.id) {
              Text('● ')
                .fontSize(13)
                .fontColor(Pal.good)
            }
            Text(e.profile.remarks.length > 0 ? e.profile.remarks : '(未命名)')
              .fontSize(15)
              .fontColor(Pal.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(e.profile.configType + ' · ' + e.profile.server + ':' + e.profile.serverPort)
            .fontSize(12)
            .fontColor(Pal.sub)
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.delayText(e))
          .fontSize(12)
          .fontColor(e.delay >= 0 ? Pal.good : Pal.sub)
      }
      .width('100%')
      .onClick(() => {
        this.pick(e);
      })
      Row({ space: 14 }) {
        Text('分享')
          .fontSize(12)
          .fontColor(Pal.accent)
          .onClick(() => {
            this.shareEntry(e);
          })
        Text('编辑')
          .fontSize(12)
          .fontColor(Pal.accent)
          .onClick(() => {
            this.editEntry(e);
          })
        Text('删除')
          .fontSize(12)
          .fontColor(Pal.bad)
          .onClick(() => {
            ServerStore.remove(e.id);
            this.hint = '已删除';
            this.rev++;
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(Pal.card)
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Text('节点')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Pal.text)
            .layoutWeight(1)
          Text('剪贴板导入')
            .fontSize(13)
            .fontColor(Pal.accent)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(15)
            .backgroundColor(Pal.accentSoft)
            .onClick(() => {
              this.importFromClipboard();
            })
          Text('粘贴导入')
            .fontSize(13)
            .fontColor(Pal.accent)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(15)
            .backgroundColor(Pal.accentSoft)
            .margin({ left: 6 })
            .onClick(() => {
              this.showImport = !this.showImport;
            })
          Text('＋ 手动')
            .fontSize(13)
            .fontColor('#FFFFFF')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(15)
            .backgroundColor(Pal.accent)
            .margin({ left: 6 })
            .onClick(() => {
              this.newEntry();
            })
        }
        .width('100%')

        Text('扫码导入：TODO（需 Scan Kit，真机迭代时补；当前用剪贴板/粘贴导入）')
          .fontSize(11)
          .fontColor(Pal.sub)
          .width('100%')
          .margin({ top: 6 })

        if (this.showImport) {
          Column() {
            TextArea({ placeholder: '粘贴节点链接，一行一条（vmess:// / vless:// / ss:// …）', text: this.importText })
              .height(110)
              .backgroundColor(Pal.chip)
              .borderRadius(10)
              .onChange((v: string) => {
                this.importText = v;
              })
            Button('导入')
              .width('100%')
              .height(42)
              .fontColor('#FFFFFF')
              .backgroundColor(Pal.accent)
              .borderRadius(12)
              .margin({ top: 8 })
              .onClick(() => {
                this.doImportText();
              })
          }
          .width('100%')
          .padding(12)
          .borderRadius(14)
          .backgroundColor(Pal.card)
          .margin({ top: 10 })
        }

        Row() {
          Text(this.hint)
            .fontSize(12)
            .fontColor(Pal.accent)
            .layoutWeight(1)
          Text(this.testing ? '测速中…' : '全部测速')
            .fontSize(12)
            .fontColor(Pal.accent)
            .onClick(() => {
              this.testAll();
            })
        }
        .width('100%')
        .margin({ top: 8 })

        if (this.entries().length === 0) {
          Text('暂无节点。点右上「剪贴板导入 / 粘贴导入 / 手动」，或去订阅页添加订阅。')
            .fontSize(13)
            .fontColor(Pal.sub)
            .width('100%')
            .margin({ top: 16 })
        }

        ForEach(this.groups(), (g: string) => {
          Text(g)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Pal.sub)
            .width('100%')
            .margin({ top: 14, bottom: 6 })
          Column({ space: 8 }) {
            ForEach(this.entriesOf(g), (e: ServerEntry) => {
              this.entryRow(e)
            }, (e: ServerEntry) => e.id)
          }
          .width('100%')
        }, (g: string) => g)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}
