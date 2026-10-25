// v2rayNG Harmony · 订阅管理页（对齐安卓订阅设置）
// 每条：备注 / 域名 / 节点数 / 上次更新 / 用量（subscription-userinfo）；
// 操作：更新、编辑、删除、启用开关。顶部：添加订阅、更新全部（显示进度）。
import { router, promptAction } from '@kit.ArkUI';
import { Subscription, SubscriptionManager } from '../model/SubscriptionManager';
import { Pal, fmtBytes, fmtExpire, fmtTime } from '../components/Ui';

function hostOf(url: string): string {
  let u: string = url;
  const p: number = u.indexOf('://');
  if (p >= 0) u = u.substring(p + 3);
  const slash: number = u.indexOf('/');
  if (slash >= 0) u = u.substring(0, slash);
  const q: number = u.indexOf('?');
  if (q >= 0) u = u.substring(0, q);
  return u.length > 0 ? u : url;
}

@Entry
@Component
struct SubscriptionsPage {
  @State rev: number = 0;
  @State msg: string = '';
  @State busy: boolean = false;
  @State refreshingAll: boolean = false;
  @State progress: string = '';
  // 编辑表单
  @State showForm: boolean = false;
  @State formId: string = '';
  @State formName: string = '';
  @State formUrl: string = '';
  @State formEnabled: boolean = true;

  private subs(): Subscription[] {
    void this.rev;
    return SubscriptionManager.getAll();
  }

  async refreshOne(s: Subscription): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.msg = '正在更新「' + s.name + '」…';
    try {
      const added: number = await SubscriptionManager.refresh(s.id);
      this.msg = '「' + s.name + '」已更新（本次新增 ' + added + ' 个节点）';
      promptAction.showToast({ message: '订阅已更新' });
    } catch (e) {
      this.msg = '更新失败：' + (e as Error).message;
    }
    this.busy = false;
    this.rev++;
  }

  async refreshAll(): Promise<void> {
    if (this.busy || this.refreshingAll) return;
    const all: Subscription[] = SubscriptionManager.getAll()
      .filter((s: Subscription) => s.enabled);
    if (all.length === 0) {
      this.msg = '没有启用的订阅';
      return;
    }
    this.refreshingAll = true;
    let ok: number = 0;
    for (let i = 0; i < all.length; i++) {
      this.progress = '更新中 (' + (i + 1) + '/' + all.length + ') ' + all[i].name;
      try {
        await SubscriptionManager.refresh(all[i].id);
        ok++;
      } catch (e) {
        // 单个失败不中断其余订阅
      }
      this.rev++;
    }
    this.refreshingAll = false;
    this.progress = '';
    this.msg = '更新全部完成：成功 ' + ok + ' / ' + all.length;
    promptAction.showToast({ message: '订阅更新完成' });
  }

  submitForm(): void {
    const name: string = this.formName.trim();
    const url: string = this.formUrl.trim();
    if (url.length === 0) {
      this.msg = '订阅地址不能为空';
      return;
    }
    if (this.formId.length > 0) {
      SubscriptionManager.update(this.formId, name.length > 0 ? name : url, url, this.formEnabled);
      this.msg = '订阅已保存';
    } else {
      const created: Subscription = SubscriptionManager.add(name.length > 0 ? name : url, url);
      if (!this.formEnabled) {
        SubscriptionManager.update(created.id, created.name, created.url, false);
      }
      this.msg = '订阅已添加，点「更新」拉取节点';
    }
    this.showForm = false;
    this.formId = '';
    this.formName = '';
    this.formUrl = '';
    this.formEnabled = true;
    this.rev++;
  }

  confirmDelete(s: Subscription): void {
    AlertDialog.show({
      title: '删除订阅',
      message: '删除「' + s.name + '」会同时删除它导入的全部节点，确定？',
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
          SubscriptionManager.remove(s.id);
          this.msg = '已删除订阅及其节点';
          this.rev++;
        },
      },
    });
  }

  usageText(s: Subscription): string {
    const parts: string[] = [];
    if (s.total > 0) {
      parts.push('已用 ' + fmtBytes(s.upload + s.download) + ' / 共 ' + fmtBytes(s.total));
    }
    if (s.expireAt > 0) {
      parts.push('到期 ' + fmtExpire(s.expireAt));
    }
    return parts.join(' · ');
  }

  @Builder subCard(s: Subscription) {
    Column() {
      Row() {
        Column() {
          Text(s.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Pal.text)
            .maxLines(1);
          Text(hostOf(s.url)).fontSize(12).fontColor(Pal.sub).maxLines(1)
            .margin({ top: 2 });
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start);
        Toggle({ type: ToggleType.Switch, isOn: s.enabled })
          .selectedColor(Pal.accent)
          .onChange((on: boolean) => {
            SubscriptionManager.update(s.id, s.name, s.url, on);
            this.rev++;
          });
      }
      .width('100%');
      Row({ space: 14 }) {
        Text('节点 ' + s.nodeCount).fontSize(12).fontColor(Pal.sub);
        Text('更新 ' + fmtTime(s.lastUpdate)).fontSize(12).fontColor(Pal.sub);
      }
      .margin({ top: 6 });
      if (this.usageText(s).length > 0) {
        Text(this.usageText(s)).fontSize(12).fontColor(Pal.sub).margin({ top: 4 });
      }
      Row({ space: 10 }) {
        Button('更新').height(32).fontSize(13)
          .backgroundColor(Pal.accentSoft).fontColor(Pal.accent)
          .enabled(s.enabled && !this.busy && !this.refreshingAll)
          .onClick(() => this.refreshOne(s));
        Button('编辑').height(32).fontSize(13)
          .backgroundColor(Pal.chip).fontColor(Pal.text)
          .onClick(() => {
            this.formId = s.id;
            this.formName = s.name;
            this.formUrl = s.url;
            this.formEnabled = s.enabled;
            this.showForm = true;
          });
        Button('删除').height(32).fontSize(13)
          .backgroundColor(Pal.chip).fontColor(Pal.bad)
          .onClick(() => this.confirmDelete(s));
      }
      .margin({ top: 10 });
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(12).borderRadius(10).backgroundColor(Pal.card)
    .margin({ bottom: 10 });
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('‹').fontSize(26).fontColor(Pal.text).padding({ left: 4, right: 10 })
          .onClick(() => router.back());
        Text('订阅管理').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Pal.text)
          .layoutWeight(1);
        Text('更新全部').fontSize(14).fontColor(Pal.accent)
          .onClick(() => this.refreshAll());
      }
      .width('100%').padding({ left: 10, right: 16, top: 12, bottom: 10 })
      .backgroundColor(Pal.card);

      if (this.progress.length > 0) {
        Text(this.progress).fontSize(12).fontColor(Pal.accent)
          .padding({ left: 14, top: 8 });
      }
      if (this.msg.length > 0) {
        Text(this.msg).fontSize(12).fontColor(Pal.sub)
          .padding({ left: 14, top: 6 });
      }

      Button(this.showForm ? '收起表单' : '＋ 添加订阅')
        .width('100%').height(42)
        .margin({ left: 12, right: 12, top: 10, bottom: 4 })
        .backgroundColor(Pal.accent).fontColor('#FFFFFF')
        .onClick(() => {
          this.showForm = !this.showForm;
          if (!this.showForm) {
            this.formId = '';
          }
        });

      if (this.showForm) {
        Column() {
          TextInput({ text: this.formName, placeholder: '订阅名称（可空，默认用地址）' })
            .height(44).backgroundColor(Pal.card).borderRadius(8)
            .onChange((v: string) => { this.formName = v; });
          TextArea({ text: this.formUrl, placeholder: '订阅地址 https://…' })
            .height(76).backgroundColor(Pal.card).borderRadius(8)
            .margin({ top: 8 })
            .onChange((v: string) => { this.formUrl = v; });
          Row() {
            Text('启用').fontSize(14).fontColor(Pal.text).layoutWeight(1);
            Toggle({ type: ToggleType.Switch, isOn: this.formEnabled })
              .selectedColor(Pal.accent)
              .onChange((on: boolean) => { this.formEnabled = on; });
          }
          .width('100%').margin({ top: 10 });
          Button(this.formId.length > 0 ? '保存修改' : '添加')
            .width('100%').height(42).margin({ top: 10 })
            .backgroundColor(Pal.accent).fontColor('#FFFFFF')
            .onClick(() => this.submitForm());
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 });
      }

      Scroll() {
        Column() {
          if (this.subs().length === 0) {
            Text('还没有订阅。点上方「添加订阅」粘贴机场订阅地址。')
              .fontSize(13).fontColor(Pal.sub)
              .padding({ top: 24 });
          }
          ForEach(this.subs(), (s: Subscription) => {
            this.subCard(s);
          }, (s: Subscription) => s.id);
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 16 });
      }
      .layoutWeight(1).width('100%');
    }
    .width('100%').height('100%').backgroundColor(Pal.bg);
  }
}
