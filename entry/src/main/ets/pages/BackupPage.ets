// v2rayNG Harmony · 备份与恢复（对齐安卓 BackupActivity 基础形态）
// 导出 = JSON{app, version, exportedAt, selectedId, servers, subscriptions, settings}
// 出口：保存到文件 / 复制到剪贴板；导入：从文件 / 从剪贴板，解析后整体替换三类数据（二次确认）。
import { router, promptAction } from '@kit.ArkUI';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ServerStore } from '../model/ServerStore';
import { SubscriptionManager } from '../model/SubscriptionManager';
import { SettingsStore } from '../model/SettingsStore';
import {
  AppSettings, CustomRules, defaultCustomRules, defaultSettings,
} from '../model/XrayConfig';
import { Pal, copyToClipboard, readClipboard } from '../components/Ui';

function readTextFile(uri: string): string {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const chunks: Uint8Array[] = [];
    let total: number = 0;
    const buf: ArrayBuffer = new ArrayBuffer(65536);
    while (true) {
      const n: number = fs.readSync(file.fd, buf, { offset: total });
      if (n <= 0) break;
      const part: Uint8Array = new Uint8Array(buf.slice(0, n));
      chunks.push(part);
      total += n;
      if (total > 16 * 1024 * 1024) throw new Error('文件过大');
    }
    const all: Uint8Array = new Uint8Array(total);
    let off: number = 0;
    for (let i = 0; i < chunks.length; i++) {
      all.set(chunks[i], off);
      off += chunks[i].length;
    }
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    return decoder.decodeToString(all);
  } finally {
    fs.closeSync(file);
  }
}

/** 从 JSON 对象消毒恢复设置（从默认值起逐字段覆盖，未知/非法字段忽略） */
function settingsFromJson(o: Record<string, Object>): AppSettings {
  const s: AppSettings = defaultSettings();
  const str = (v: Object | undefined, dflt: string): string =>
    typeof v === 'string' ? (v as string) : dflt;
  const num = (v: Object | undefined, dflt: number): number => {
    const n: number = Number(v ?? dflt);
    return isNaN(n) ? dflt : n;
  };
  const bool = (v: Object | undefined, dflt: boolean): boolean =>
    typeof v === 'boolean' ? (v as boolean) : dflt;
  s.socksPort = num(o['socksPort'], s.socksPort);
  s.httpPort = num(o['httpPort'], s.httpPort);
  const rm: string = str(o['routingMode'], 'rule');
  s.routingMode = (rm === 'global' || rm === 'direct') ? rm : 'rule';
  s.enableUdp = bool(o['enableUdp'], s.enableUdp);
  s.sniffingEnabled = bool(o['sniffingEnabled'], s.sniffingEnabled);
  s.ipv6Enabled = bool(o['ipv6Enabled'], s.ipv6Enabled);
  s.localDns = str(o['localDns'], s.localDns);
  s.remoteDns = str(o['remoteDns'], s.remoteDns);
  s.subUpdateHours = num(o['subUpdateHours'], s.subUpdateHours);
  s.tunEnabled = bool(o['tunEnabled'], s.tunEnabled);
  s.logLevel = str(o['logLevel'], s.logLevel);
  const pm: string = str(o['perAppMode'], 'off');
  s.perAppMode = (pm === 'block' || pm === 'allow') ? pm : 'off';
  s.perAppList = str(o['perAppList'], s.perAppList);
  const crObj: Object | undefined = o['customRules'];
  if (crObj !== undefined) {
    const cr: CustomRules = defaultCustomRules();
    const co: Record<string, Object> = crObj as Object as Record<string, Object>;
    cr.directDomain = str(co['directDomain'], '');
    cr.proxyDomain = str(co['proxyDomain'], '');
    cr.blockDomain = str(co['blockDomain'], '');
    cr.directIp = str(co['directIp'], '');
    cr.proxyIp = str(co['proxyIp'], '');
    s.customRules = cr;
  }
  const tm: string = str(o['themeMode'], 'system');
  s.themeMode = (tm === 'light' || tm === 'dark') ? tm : 'system';
  s.autoConnect = bool(o['autoConnect'], false);
  return s;
}

@Entry
@Component
struct BackupPage {
  @State msg: string = '';
  @State busy: boolean = false;

  private buildBackupJson(): string {
    const data: Record<string, Object> = {};
    data['app'] = 'v2rayNG-Harmony';
    data['version'] = 1;
    data['exportedAt'] = Date.now();
    data['selectedId'] = ServerStore.getSelectedId();
    data['servers'] = ServerStore.snapshotRaw() as Object as Object;
    data['subscriptions'] = SubscriptionManager.getAll() as Object as Object;
    data['settings'] = SettingsStore.get() as Object as Object;
    return JSON.stringify(data, null, 2);
  }

  async exportToFile(): Promise<void> {
    try {
      const now: Date = new Date();
      const pad = (n: number): string => (n < 10 ? '0' : '') + n;
      const name: string = 'v2rayng-backup-' + now.getFullYear() + pad(now.getMonth() + 1) +
        pad(now.getDate()) + '-' + pad(now.getHours()) + pad(now.getMinutes()) + '.json';
      const opt = new picker.DocumentSaveOptions();
      opt.newFileNames = [name];
      const viewPicker = new picker.DocumentViewPicker(getContext(this));
      const uris: Array<string> = await viewPicker.save(opt);
      if (uris.length === 0) {
        this.msg = '已取消导出';
        return;
      }
      const text: string = this.buildBackupJson();
      const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
      this.msg = '备份已保存：' + name;
      promptAction.showToast({ message: '备份已保存' });
    } catch (e) {
      this.msg = '导出失败：' + (e as Error).message;
    }
  }

  exportToClipboard(): void {
    copyToClipboard(this.buildBackupJson());
    this.msg = '备份 JSON 已复制到剪贴板';
    promptAction.showToast({ message: '备份已复制' });
  }

  async importFromFile(): Promise<void> {
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.fileSuffixFilters = ['.json', '.txt'];
      opt.maxSelectNumber = 1;
      const viewPicker = new picker.DocumentViewPicker(getContext(this));
      const uris: Array<string> = await viewPicker.select(opt);
      if (uris.length === 0) {
        this.msg = '已取消导入';
        return;
      }
      const text: string = readTextFile(uris[0]);
      this.confirmRestore(text);
    } catch (e) {
      this.msg = '读取文件失败：' + (e as Error).message;
    }
  }

  async importFromClipboard(): Promise<void> {
    const text: string = await readClipboard();
    if (text.trim().length === 0) {
      this.msg = '剪贴板为空';
      return;
    }
    this.confirmRestore(text);
  }

  private confirmRestore(text: string): void {
    // 先校验可解析，避免确认后才发现格式不对
    try {
      const parsed: Object = JSON.parse(text) as Object;
      if (!Array.isArray(parsed) &&
        (parsed as Record<string, Object>)['servers'] === undefined &&
        (parsed as Record<string, Object>)['subscriptions'] === undefined) {
        this.msg = '不是有效的备份文件（缺少 servers/subscriptions）';
        return;
      }
    } catch (e) {
      this.msg = '备份内容不是合法 JSON';
      return;
    }
    AlertDialog.show({
      title: '恢复备份',
      message: '恢复将整体覆盖当前的全部节点、订阅与设置，确定继续？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '覆盖恢复',
        fontColor: '#C0392B',
        action: () => {
          this.doRestore(text);
        },
      },
    });
  }

  private doRestore(text: string): void {
    try {
      const parsed: Object = JSON.parse(text) as Object;
      let serverCount: number = 0;
      let subCount: number = 0;
      let settingsRestored: boolean = false;
      if (Array.isArray(parsed)) {
        // 兼容旧格式：仅节点数组（v1.1 的剪贴板备份）
        serverCount = ServerStore.restoreRaw(parsed as Object[], '');
      } else {
        const root: Record<string, Object> = parsed as Record<string, Object>;
        const servers: Object | undefined = root['servers'];
        if (Array.isArray(servers)) {
          serverCount = ServerStore.restoreRaw(servers as Object[],
            String(root['selectedId'] ?? ''));
        }
        const subs: Object | undefined = root['subscriptions'];
        if (Array.isArray(subs)) {
          subCount = SubscriptionManager.restoreAll(subs as Object[]);
        }
        const settingsObj: Object | undefined = root['settings'];
        if (settingsObj !== undefined) {
          SettingsStore.save(settingsFromJson(settingsObj as Object as Record<string, Object>));
          settingsRestored = true;
        }
      }
      this.msg = '恢复完成：节点 ' + serverCount + '、订阅 ' + subCount +
        (settingsRestored ? '、设置已恢复' : '');
      promptAction.showToast({ message: '备份恢复完成' });
      setTimeout(() => {
        router.back();
      }, 600);
    } catch (e) {
      this.msg = '恢复失败：' + (e as Error).message;
    }
  }

  @Builder actionBtn(label: string, desc: string, action: () => void) {
    Column() {
      Text(label).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Pal.text);
      Text(desc).fontSize(12).fontColor(Pal.sub).margin({ top: 3 });
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding(14).borderRadius(10).backgroundColor(Pal.card)
    .margin({ bottom: 10 })
    .onClick(() => action());
  }

  build() {
    Column() {
      Row() {
        Text('‹').fontSize(26).fontColor(Pal.text).padding({ left: 4, right: 10 })
          .onClick(() => router.back());
        Text('备份与恢复').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Pal.text)
          .layoutWeight(1);
      }
      .width('100%').padding({ left: 10, right: 16, top: 12, bottom: 10 })
      .backgroundColor(Pal.card);

      Scroll() {
        Column() {
          Text('导出备份（节点 + 订阅 + 设置）').fontSize(13).fontWeight(FontWeight.Bold)
            .fontColor(Pal.sub).margin({ bottom: 8 });
          this.actionBtn('保存到文件', '生成 JSON 备份文件，可存到下载目录长期保存',
            () => { this.exportToFile(); });
          this.actionBtn('复制到剪贴板', '把备份 JSON 复制到剪贴板，自行粘贴保存',
            () => { this.exportToClipboard(); });
          Text('导入恢复').fontSize(13).fontWeight(FontWeight.Bold)
            .fontColor(Pal.sub).margin({ top: 10, bottom: 8 });
          this.actionBtn('从文件恢复', '选择之前导出的 JSON 备份文件',
            () => { this.importFromFile(); });
          this.actionBtn('从剪贴板恢复', '剪贴板里是备份 JSON 时使用',
            () => { this.importFromClipboard(); });
          Text('恢复会整体覆盖当前数据，请先确认备份内容可信。订阅恢复仅恢复订阅记录本身，' +
            '节点会按备份中的快照一并恢复，无需重新拉取。')
            .fontSize(12).fontColor(Pal.sub).margin({ top: 6 });
          if (this.msg.length > 0) {
            Text(this.msg).fontSize(13).fontColor(Pal.accent).margin({ top: 12 });
          }
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 14, bottom: 20 });
      }
      .layoutWeight(1).width('100%');
    }
    .width('100%').height('100%').backgroundColor(Pal.bg);
  }
}
