// v2rayNG Harmony · 订阅页：列表、添加/编辑/删除/更新
import { SubscriptionManager, Subscription } from '../model/SubscriptionManager';
import { LogStore } from '../model/LogStore';
import { Pal, fmtTime, fmtExpire, fmtBytes } from './Ui';

@Component
export struct SubsTab {
  @Prop @Watch('onTick') tick: number = 0;
  @State rev: number = 0;
  @State msg: string = '';
  @State busy: boolean = false;
  @State showForm: boolean = false;
  @State editId: string = '';
  @State formName: string = '';
  @State formUrl: string = '';
  @State formEnabled: boolean = true;

  onTick(): void {
    this.rev++;
  }

  subs(): Subscription[] {
    return SubscriptionManager.getAll();
  }

  openAdd(): void {
    this.editId = '';
    this.formName = '';
    this.formUrl = '';
    this.formEnabled = true;
    this.showForm = true;
  }

  openEdit(s: Subscription): void {
    this.editId = s.id;
    this.formName = s.name;
    this.formUrl = s.url;
    this.formEnabled = s.enabled;
    this.showForm = true;
  }

  async saveForm(): Promise<void> {
    const url: string = this.formUrl.trim();
    if (url.length === 0) {
      this.msg = '请填写订阅链接';
      return;
    }
    if (this.editId.length === 0) {
      const sub: Subscription = SubscriptionManager.add(this.formName.trim(), url);
      this.showForm = false;
      this.busy = true;
      this.msg = '拉取中…';
      try {
        const n: number = await SubscriptionManager.refresh(sub.id);
        this.msg = '添加成功，共 ' + n + ' 个节点';
      } catch (e) {
        this.msg = '已添加，但拉取失败: ' + (e instanceof Error ? e.message : String(e));
      }
      this.busy = false;
    } else {
      SubscriptionManager.update(this.editId, this.formName.trim(), url, this.formEnabled);
      this.showForm = false;
      this.msg = '已保存';
    }
    this.rev++;
  }

  async refreshOne(s: Subscription): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.msg = '更新 ' + s.name + '…';
    try {
      const n: number = await SubscriptionManager.refresh(s.id);
      this.msg = s.name + ' 更新完成：' + n + ' 个节点';
    } catch (e) {
      this.msg = s.name + ' 更新失败: ' + (e instanceof Error ? e.message : String(e));
      LogStore.push('订阅', this.msg);
    }
    this.busy = false;
    this.rev++;
  }

  async refreshAll(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    await SubscriptionManager.refreshAll();
    this.busy = false;
    this.msg = '全部订阅更新完成';
    this.rev++;
  }

  trafficText(s: Subscription): string {
    if (s.total <= 0) return '';
    const used: number = s.upload + s.download;
    return '已用 ' + fmtBytes(used) + ' / ' + fmtBytes(s.total) + ' · 到期 ' + fmtExpire(s.expireAt);
  }

  @Builder
  subCard(s: Subscription) {
    Column() {
      Row() {
        Text(s.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(s.enabled ? '启用' : '停用')
          .fontSize(11)
          .fontColor(s.enabled ? Pal.good : Pal.sub)
      }
      .width('100%')
      Text(s.url)
        .fontSize(11)
        .fontColor(Pal.sub)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 4 })
      Text(s.nodeCount + ' 个节点 · 更新于 ' + fmtTime(s.lastUpdate) +
        (this.trafficText(s).length > 0 ? ' · ' + this.trafficText(s) : ''))
        .fontSize(12)
        .fontColor(Pal.sub)
        .width('100%')
        .margin({ top: 4 })
      Row({ space: 10 }) {
        Text('刷新')
          .fontSize(13)
          .fontColor(Pal.accent)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(15)
          .backgroundColor(Pal.accentSoft)
          .onClick(() => {
            this.refreshOne(s);
          })
        Text('编辑')
          .fontSize(13)
          .fontColor(Pal.accent)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(15)
          .backgroundColor(Pal.chip)
          .onClick(() => {
            this.openEdit(s);
          })
        Text('删除')
          .fontSize(13)
          .fontColor(Pal.bad)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(15)
          .backgroundColor(Pal.chip)
          .onClick(() => {
            SubscriptionManager.remove(s.id);
            this.msg = '已删除 ' + s.name + '（含其节点）';
            this.rev++;
          })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor(Pal.card)
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Text('订阅')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Pal.text)
            .layoutWeight(1)
          Text('全部刷新')
            .fontSize(13)
            .fontColor(Pal.accent)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(15)
            .backgroundColor(Pal.accentSoft)
            .onClick(() => {
              this.refreshAll();
            })
          Text(this.showForm ? '收起' : '＋ 添加')
            .fontSize(13)
            .fontColor('#FFFFFF')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(15)
            .backgroundColor(Pal.accent)
            .margin({ left: 8 })
            .onClick(() => {
              if (this.showForm) {
                this.showForm = false;
              } else {
                this.openAdd();
              }
            })
        }
        .width('100%')

        if (this.showForm) {
          Column() {
            TextInput({ placeholder: '订阅名称（可空）', text: this.formName })
              .height(44)
              .backgroundColor(Pal.chip)
              .borderRadius(10)
              .onChange((v: string) => {
                this.formName = v;
              })
            TextInput({ placeholder: '订阅链接 https://…', text: this.formUrl })
              .height(44)
              .backgroundColor(Pal.chip)
              .borderRadius(10)
              .margin({ top: 8 })
              .onChange((v: string) => {
                this.formUrl = v;
              })
            Row() {
              Text('启用')
                .fontSize(14)
                .fontColor(Pal.text)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.formEnabled })
                .onChange((on: boolean) => {
                  this.formEnabled = on;
                })
            }
            .width('100%')
            .margin({ top: 8 })
            Button(this.busy ? '处理中…' : (this.editId.length === 0 ? '添加并拉取' : '保存'))
              .width('100%')
              .height(44)
              .fontColor('#FFFFFF')
              .backgroundColor(Pal.accent)
              .borderRadius(12)
              .margin({ top: 10 })
              .onClick(() => {
                this.saveForm();
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor(Pal.card)
          .margin({ top: 12 })
        }

        if (this.msg.length > 0) {
          Text(this.msg)
            .fontSize(12)
            .fontColor(Pal.accent)
            .width('100%')
            .margin({ top: 10 })
        }

        if (this.subs().length === 0) {
          Text('暂无订阅。点右上「＋ 添加」添加订阅链接。')
            .fontSize(13)
            .fontColor(Pal.sub)
            .width('100%')
            .margin({ top: 16 })
        }

        Column({ space: 10 }) {
          ForEach(this.subs(), (s: Subscription) => {
            this.subCard(s)
          }, (s: Subscription) => s.id)
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}
