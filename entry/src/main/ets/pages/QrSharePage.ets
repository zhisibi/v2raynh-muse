// v2rayNG Harmony · 节点二维码分享页
// 用 @kit.ScanKit generateBarcode.createBarcode 生成二维码（真实生成路径）；
// 生成失败时降级提示并自动复制链接。
import { router, promptAction } from '@kit.ArkUI';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { ServerStore } from '../model/ServerStore';
import { toUri } from '../model/UriParser';
import { Pal, copyToClipboard } from '../components/Ui';

interface QrParams {
  id: string;
}

@Entry
@Component
struct QrSharePage {
  @State nodeName: string = '';
  @State link: string = '';
  @State qrImage: image.PixelMap | undefined = undefined;
  @State genFailed: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as QrParams;
    const entry = ServerStore.getById(params !== undefined && params.id !== undefined ? params.id : '');
    if (entry === undefined) {
      this.genFailed = true;
      return;
    }
    this.nodeName = entry.profile.remarks;
    this.link = toUri(entry.profile);
    const options: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      width: 660,
      height: 660,
    };
    generateBarcode.createBarcode(this.link, options).then((pm: image.PixelMap) => {
      this.qrImage = pm;
    }).catch(() => {
      this.genFailed = true;
      if (this.link.length > 0) {
        copyToClipboard(this.link);
        promptAction.showToast({ message: '二维码生成失败，已复制分享链接' });
      }
    });
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('‹').fontSize(26).fontColor(Pal.text).padding({ left: 4, right: 10 })
          .onClick(() => router.back());
        Text('分享二维码').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Pal.text)
          .layoutWeight(1);
      }
      .width('100%').padding({ left: 10, right: 16, top: 12, bottom: 10 })
      .backgroundColor(Pal.card);

      Column() {
        Text(this.nodeName).fontSize(17).fontWeight(FontWeight.Bold).fontColor(Pal.text)
          .maxLines(2).textAlign(TextAlign.Center);
        if (this.qrImage !== undefined) {
          Image(this.qrImage).width(260).height(260).margin({ top: 20, bottom: 20 })
            .backgroundColor('#FFFFFF');
        } else if (this.genFailed) {
          Text('二维码生成失败').fontSize(14).fontColor(Pal.bad).margin({ top: 40, bottom: 40 });
        } else {
          Text('正在生成二维码…').fontSize(14).fontColor(Pal.sub).margin({ top: 40, bottom: 40 });
        }
        Text('分享链接').fontSize(13).fontColor(Pal.sub).alignSelf(ItemAlign.Start);
        Text(this.link).fontSize(12).fontColor(Pal.text).width('100%')
          .padding(10).borderRadius(8).backgroundColor(Pal.card)
          .margin({ top: 6, bottom: 14 });
        Button('复制链接').width('100%').height(44)
          .backgroundColor(Pal.accent).fontColor('#FFFFFF')
          .onClick(() => {
            copyToClipboard(this.link);
            promptAction.showToast({ message: '链接已复制' });
          });
      }
      .width('100%').padding({ left: 16, right: 16, top: 18 })
      .layoutWeight(1);
    }
    .width('100%').height('100%').backgroundColor(Pal.bg);
  }
}
