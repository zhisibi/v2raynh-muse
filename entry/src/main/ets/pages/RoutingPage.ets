// v2rayNG Harmony · 路由设置页（对齐安卓 RoutingSettingActivity 基础形态）
// 路由模式与 SettingsStore.routingMode 同源；自定义规则五组多行文本存 customRules，
// 由 XrayConfig 在生成配置时插到模式规则之前（拦截→block、直连→direct、代理→proxy）。
import { router, promptAction } from '@kit.ArkUI';
import { SettingsStore } from '../model/SettingsStore';
import { AppSettings, CustomRules, defaultCustomRules, RoutingMode } from '../model/XrayConfig';
import { Pal } from '../components/Ui';

@Entry
@Component
struct RoutingPage {
  @State mode: RoutingMode = 'rule';
  @State directDomain: string = '';
  @State proxyDomain: string = '';
  @State blockDomain: string = '';
  @State directIp: string = '';
  @State proxyIp: string = '';

  aboutToAppear(): void {
    const s: AppSettings = SettingsStore.get();
    this.mode = s.routingMode;
    const cr: CustomRules = s.customRules !== undefined ? s.customRules : defaultCustomRules();
    this.directDomain = cr.directDomain;
    this.proxyDomain = cr.proxyDomain;
    this.blockDomain = cr.blockDomain;
    this.directIp = cr.directIp;
    this.proxyIp = cr.proxyIp;
  }

  save(): void {
    const s: AppSettings = SettingsStore.get();
    s.routingMode = this.mode;
    const cr: CustomRules = defaultCustomRules();
    cr.directDomain = this.directDomain;
    cr.proxyDomain = this.proxyDomain;
    cr.blockDomain = this.blockDomain;
    cr.directIp = this.directIp;
    cr.proxyIp = this.proxyIp;
    s.customRules = cr;
    SettingsStore.save(s);
    promptAction.showToast({ message: '路由设置已保存（重连后生效）' });
  }

  @Builder segBtn(label: string, value: RoutingMode) {
    Text(label)
      .fontSize(13)
      .fontColor(this.mode === value ? '#FFFFFF' : Pal.text)
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.mode === value ? Pal.accent : Pal.chip)
      .onClick(() => {
        this.mode = value;
      });
  }

  @Builder ruleEditor(title: string, hint: string, value: string, onChange: (v: string) => void) {
    Column() {
      Text(title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(Pal.text);
      Text(hint).fontSize(11).fontColor(Pal.sub).margin({ top: 2, bottom: 6 });
      TextArea({ text: value, placeholder: '每行一条，留空表示不启用' })
        .fontSize(13).height(96).width('100%')
        .backgroundColor(Pal.card).borderRadius(8)
        .onChange((v: string) => onChange(v));
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(Pal.bg);
  }

  build() {
    Column() {
      Row() {
        Text('‹').fontSize(26).fontColor(Pal.text).padding({ left: 4, right: 10 })
          .onClick(() => router.back());
        Text('路由设置').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Pal.text)
          .layoutWeight(1);
        Text('保存').fontSize(15).fontColor(Pal.accent)
          .onClick(() => this.save());
      }
      .width('100%').padding({ left: 10, right: 16, top: 12, bottom: 10 })
      .backgroundColor(Pal.card);

      Scroll() {
        Column() {
          Column() {
            Text('路由模式').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Pal.text);
            Text('规则：按内置规则分流；全局：全部流量走代理；直连：仅代理所选节点（其余直连）。')
              .fontSize(11).fontColor(Pal.sub).margin({ top: 2, bottom: 8 });
            Row({ space: 8 }) {
              this.segBtn('规则', 'rule');
              this.segBtn('全局', 'global');
              this.segBtn('直连', 'direct');
            }
          }
          .width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 14, right: 14, top: 12, bottom: 12 });

          Divider().color(Pal.line).margin({ left: 14, right: 14 });
          this.ruleEditor('拦截域名', '命中后拦截（block），如 ads.example.com、geosite:category-ads',
            this.blockDomain, (v: string) => { this.blockDomain = v; });
          Divider().color(Pal.line).margin({ left: 14, right: 14 });
          this.ruleEditor('直连域名', '命中后直连，如 example.com、geosite:cn',
            this.directDomain, (v: string) => { this.directDomain = v; });
          Divider().color(Pal.line).margin({ left: 14, right: 14 });
          this.ruleEditor('代理域名', '命中后走代理，如 geosite:google、example.org',
            this.proxyDomain, (v: string) => { this.proxyDomain = v; });
          Divider().color(Pal.line).margin({ left: 14, right: 14 });
          this.ruleEditor('直连 IP', '命中后直连，如 192.168.0.0/16、geoip:cn',
            this.directIp, (v: string) => { this.directIp = v; });
          Divider().color(Pal.line).margin({ left: 14, right: 14 });
          this.ruleEditor('代理 IP', '命中后走代理，如 8.8.8.8、geoip:telegram',
            this.proxyIp, (v: string) => { this.proxyIp = v; });
          Text('自定义规则在生成配置时插入到模式规则之前，优先级高于内置规则；改动后需断开重连生效。')
            .fontSize(11).fontColor(Pal.sub)
            .padding({ left: 14, right: 14, top: 10, bottom: 20 });
        }
        .width('100%');
      }
      .layoutWeight(1).width('100%');
    }
    .width('100%').height('100%').backgroundColor(Pal.bg);
  }
}
