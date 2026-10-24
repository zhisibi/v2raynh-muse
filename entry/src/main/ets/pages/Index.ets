// v2rayNG Harmony · 主界面：单页 + 四 Tab（首页/节点/订阅/我的），经典 pages 注册
import { HomeTab } from '../components/HomeTab';
import { ServersTab } from '../components/ServersTab';
import { SubsTab } from '../components/SubsTab';
import { MineTab } from '../components/MineTab';
import { ConnectManager } from '../service/ConnectManager';
import { Pal } from '../components/Ui';

@Entry
@Component
struct Index {
  @State tab: number = 0;
  @State tick: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      this.tick++;
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  @Builder
  tabBarItem(idx: number, label: string, glyph: string) {
    Column() {
      Text(glyph)
        .fontSize(21)
        .opacity(this.tab === idx ? 1 : 0.55)
      Text(label)
        .fontSize(11)
        .fontColor(this.tab === idx ? Pal.accent : Pal.sub)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding({ top: 7, bottom: 9 })
    .onClick(() => {
      this.tab = idx;
    })
  }

  build() {
    Column() {
      Row() {
        Text('v2rayNG')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Pal.text)
          .layoutWeight(1)
        Row() {
          Circle()
            .width(8)
            .height(8)
            .fill(ConnectManager.status() === 'running' ? Pal.good : Pal.sub)
          Text(ConnectManager.status() === 'running' ? '已连接' : '未连接')
            .fontSize(12)
            .fontColor(Pal.sub)
            .margin({ left: 5 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })

      Column() {
        if (this.tab === 0) {
          HomeTab({ tick: this.tick })
        } else if (this.tab === 1) {
          ServersTab({ tick: this.tick })
        } else if (this.tab === 2) {
          SubsTab({ tick: this.tick })
        } else {
          MineTab({ tick: this.tick })
        }
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        this.tabBarItem(0, '首页', '🏠')
        this.tabBarItem(1, '节点', '🌐')
        this.tabBarItem(2, '订阅', '📋')
        this.tabBarItem(3, '我的', '⚙️')
      }
      .width('100%')
      .backgroundColor(Pal.bg)
      .border({ width: { top: 1 }, color: Pal.line })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Pal.bg)
  }
}
