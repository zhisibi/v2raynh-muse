// v2rayNG Harmony · 关于页
import { router } from '@kit.ArkUI';
import { coreVersion, isNativeAvailable } from '../model/CoreBridge';
import { Pal } from '../components/Ui';

@Entry
@Component
struct AboutPage {
  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(15)
          .fontColor(Pal.accent)
          .onClick(() => {
            router.back();
          })
        Text('关于')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Pal.text)
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 10 })

      Column() {
        Image($r('app.media.icon'))
          .width(72)
          .height(72)
          .borderRadius(16)
        Text('v2rayNG')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Pal.text)
          .margin({ top: 12 })
        Text('HarmonyOS NEXT 移植版 1.1.0 (101)')
          .fontSize(13)
          .fontColor(Pal.sub)
          .margin({ top: 6 })
        Text('包名 com.bosh.v2rayng')
          .fontSize(12)
          .fontColor(Pal.sub)
          .margin({ top: 4 })
        Text('Xray 内核：' + (isNativeAvailable() ? (coreVersion().length > 0 ? coreVersion() : '已加载') : '未编译/未加载（UI 降级模式）'))
          .fontSize(12)
          .fontColor(Pal.sub)
          .margin({ top: 4 })
        Text('移植自 Android v2rayNG 2.3.13（2dust，GPL-3.0）。核心为 XTLS Xray-core，经 OpenHarmony Go 工具链编译为 libxray.so，TUN 转发用 hev-socks5-tunnel。geoip/geosite 数据文件已内置，首次启动自动释放到应用数据目录 xray_assets。')
          .fontSize(12)
          .fontColor(Pal.sub)
          .margin({ top: 16 })
      }
      .width('100%')
      .padding(18)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Pal.bg)
  }
}
