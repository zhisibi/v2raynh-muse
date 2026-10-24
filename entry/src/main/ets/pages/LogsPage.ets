// v2rayNG Harmony · 日志页：查看/清空/导出（复制剪贴板 + 落盘路径提示）
// TODO：导出亦可走系统保存/分享（picker/ShareKit），真机迭代时补；现版本剪贴板+落盘已可回传定位。
import { router } from '@kit.ArkUI';
import { LogStore, LogLine } from '../model/LogStore';
import { Pal, copyToClipboard } from '../components/Ui';

@Entry
@Component
struct LogsPage {
  @State lines: LogLine[] = [];
  @State msg: string = '';
  private listener: () => void = () => {
    this.lines = LogStore.getAll();
  };

  aboutToAppear(): void {
    this.lines = LogStore.getAll();
    LogStore.subscribe(this.listener);
  }

  aboutToDisappear(): void {
    LogStore.unsubscribe(this.listener);
  }

  async exportLogs(): Promise<void> {
    const text: string = LogStore.exportText();
    const ok: boolean = await copyToClipboard(text);
    this.msg = ok ? '日志已复制到剪贴板' : '复制失败';
    if (LogStore.filePath().length > 0) {
      this.msg += '；落盘文件：' + LogStore.filePath();
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(15)
          .fontColor(Pal.accent)
          .onClick(() => {
            router.back();
          })
        Text('运行日志')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Pal.text)
          .margin({ left: 12 })
          .layoutWeight(1)
        Text('导出')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(15)
          .backgroundColor(Pal.accent)
          .onClick(() => {
            this.exportLogs();
          })
        Text('清空')
          .fontSize(13)
          .fontColor(Pal.bad)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(15)
          .backgroundColor(Pal.chip)
          .margin({ left: 8 })
          .onClick(() => {
            LogStore.clear();
            this.lines = [];
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 10 })

      if (this.msg.length > 0) {
        Text(this.msg)
          .fontSize(12)
          .fontColor(Pal.accent)
          .width('100%')
          .padding({ left: 14, right: 14 })
      }

      Scroll() {
        Column() {
          if (this.lines.length === 0) {
            Text('暂无日志')
              .fontSize(13)
              .fontColor(Pal.sub)
          }
          ForEach(this.lines, (l: LogLine, idx: number) => {
            Text(l.time + ' [' + l.tag + '] ' + l.msg)
              .fontSize(12)
              .fontColor(Pal.text)
              .width('100%')
              .margin({ top: 4 })
          }, (l: LogLine, idx: number) => String(idx) + l.time + l.msg)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Pal.bg)
  }
}
