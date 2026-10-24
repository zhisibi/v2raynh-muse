// v2rayNG Harmony · NAPI 桥的 ArkTS 声明与容错封装
// .so 名 'libv2rayng_core.so'（CMakeLists 的 add_library(v2rayng_core ...)）；
// native 不可用时（核心未编译）所有调用返回安全默认值，UI 降级运行。
import nativeModule from 'libv2rayng_core.so';

interface NativeCore {
  attachTunFd(fd: number, mtu: number): boolean;
  startXray(configJson: string, assetDir: string): boolean;
  stopXray(): void;
  isRunning(): boolean;
  coreVersion(): string;
  lastError(): string;
  queryTraffic(): string;
  testDelay(configJson: string, url: string, timeoutMs: number): number;
  startTun(socksPort: number, mtu: number): boolean;
  stopTun(): void;
}

const nativeCore: NativeCore = nativeModule as Object as NativeCore;

export function attachTunFd(fd: number, mtu: number): boolean {
  try {
    return Boolean(nativeCore.attachTunFd(fd, mtu));
  } catch (e) {
    return false;
  }
}

export function startXray(configJson: string, assetDir: string): boolean {
  try {
    return Boolean(nativeCore.startXray(configJson, assetDir));
  } catch (e) {
    return false;
  }
}

export function stopXray(): void {
  try {
    nativeCore.stopXray();
  } catch (e) {
    // 忽略
  }
}

export function isRunning(): boolean {
  try {
    return Boolean(nativeCore.isRunning());
  } catch (e) {
    return false;
  }
}

export function coreVersion(): string {
  try {
    return String(nativeCore.coreVersion());
  } catch (e) {
    return '';
  }
}

export function lastError(): string {
  try {
    return String(nativeCore.lastError());
  } catch (e) {
    return '';
  }
}

/** 返回 {"up","down","upTotal","downTotal",...} 累计字节 JSON（桥给累计值，速率由 UI 差分；不可用时 {}） */
export function queryTraffic(): string {
  try {
    return String(nativeCore.queryTraffic());
  } catch (e) {
    return '{}';
  }
}

/** 用给定配置实测延迟（ms），不可用返回 -1 */
export function testDelay(configJson: string, url: string, timeoutMs: number): number {
  try {
    return Number(nativeCore.testDelay(configJson, url, timeoutMs));
  } catch (e) {
    return -1;
  }
}

/** 启动 hev-socks5-tunnel（TUN fd -> SOCKS），符号缺失返回 false */
export function startTun(socksPort: number, mtu: number): boolean {
  try {
    return Boolean(nativeCore.startTun(socksPort, mtu));
  } catch (e) {
    return false;
  }
}

export function stopTun(): void {
  try {
    nativeCore.stopTun();
  } catch (e) {
    // 忽略
  }
}

export function isNativeAvailable(): boolean {
  try {
    void nativeCore.coreVersion();
    return true;
  } catch (e) {
    return false;
  }
}
