/*
 * v2rayNG Harmony · hev-socks5-tunnel 适配层
 *
 * 导出 NAPI 桥（entry/src/main/cpp/xray_napi.cpp）约定的 C ABI：
 *   int  HevTunnelStart(const char *configYaml, int tunFd);
 *   void HevTunnelStop(void);
 *   int  HevTunnelLastRc(void);   // v1.1.1 诊断：hev 线程最近一次退出码
 *   int  HevTunnelRunning(void);  // v1.1.1 诊断：hev 线程是否还活着
 *
 * 上游库化入口（hev-socks5-tunnel/src/hev-main.h）：
 *   int  hev_socks5_tunnel_main_from_str(const unsigned char *config_str,
 *                                        unsigned int config_len, int tun_fd);
 *        —— 阻塞式：解析 YAML 配置后跑 lwIP + socks5 转发事件循环，
 *           直到 hev_socks5_tunnel_quit() 被调用或出错才返回。
 *   void hev_socks5_tunnel_quit(void);
 *
 * 因此 adapter 内部起一个 pthread 跑 main_from_str，Start 立即返回；
 * Stop 调 quit 并 pthread_join 等线程退出。
 *
 * v1.1.1 诊断增强：
 *   - 原子标志 hev_running：线程启动置 1、退出清 0 并把返回码存入
 *     hev_last_rc，供 NAPI tunStatus() 回显——区分「假 running」与真活着。
 *   - 日志落地：线程函数开头读环境变量 HEV_LOG_PATH（NAPI 的 StartTun
 *     在调 Start 前 setenv 为 <logDir>/hev.log），open 后 dup2 到
 *     stderr(2)，hev 的 debug 日志（yaml misc.log-level: debug）随之
 *     落盘；扩展在探针时会把 hev.log 尾部并入 vpn_diag.txt。
 *
 * tunFd 所有权：Start 成功后 fd 归 hev 所有（hev 在 fini 时 close），
 * adapter 与 NAPI 侧都不得再 close；Start 失败（线程未起或配置非法）
 * 时 fd 仍归调用方（NAPI 侧负责 close）。
 * 与 Android v2rayNG 的差异：安卓是独立进程 + JNI 传 fd；鸿蒙是同进程
 * 共享库（VpnExtensionAbility 进程内 dlopen）。
 */

#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "hev-main.h"

static pthread_mutex_t hev_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_t hev_thread;
static int hev_thread_started = 0;
static char *hev_config = NULL;
static int hev_tun_fd = -1;

/* 诊断状态（跨线程，用 C11 原子量） */
static atomic_int hev_running_flag = 0;
static atomic_int hev_last_rc_val = -999;

static void
hev_redirect_stderr_to_log (void)
{
    const char *path = getenv ("HEV_LOG_PATH");
    if (path == NULL || path[0] == '\0')
        return;
    int fd = open (path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0)
        return;
    dup2 (fd, 2);
    if (fd > 2)
        close (fd);
    fprintf (stderr, "[hev_adapter] stderr redirected to %s\n", path);
    fflush (stderr);
}

static void *
hev_thread_main (void *arg)
{
    (void)arg;
    hev_redirect_stderr_to_log ();
    atomic_store (&hev_running_flag, 1);
    int rc = hev_socks5_tunnel_main_from_str (
        (const unsigned char *)hev_config,
        (unsigned int)strlen (hev_config), hev_tun_fd);
    atomic_store (&hev_last_rc_val, rc);
    atomic_store (&hev_running_flag, 0);
    fprintf (stderr, "[hev_adapter] hev main exited rc=%d\n", rc);
    fflush (stderr);
    return NULL;
}

int
HevTunnelStart (const char *configYaml, int tunFd)
{
    if (configYaml == NULL || tunFd < 0)
        return -1;

    pthread_mutex_lock (&hev_mu);
    if (hev_thread_started) {
        pthread_mutex_unlock (&hev_mu);
        return -2; /* already running */
    }
    free (hev_config);
    hev_config = strdup (configYaml);
    if (hev_config == NULL) {
        pthread_mutex_unlock (&hev_mu);
        return -1;
    }
    hev_tun_fd = tunFd;
    atomic_store (&hev_last_rc_val, -1);
    if (pthread_create (&hev_thread, NULL, hev_thread_main, NULL) != 0) {
        free (hev_config);
        hev_config = NULL;
        hev_tun_fd = -1;
        pthread_mutex_unlock (&hev_mu);
        return -1;
    }
    hev_thread_started = 1;
    pthread_mutex_unlock (&hev_mu);
    return 0;
}

void
HevTunnelStop (void)
{
    pthread_mutex_lock (&hev_mu);
    if (!hev_thread_started) {
        pthread_mutex_unlock (&hev_mu);
        return;
    }
    pthread_mutex_unlock (&hev_mu);

    hev_socks5_tunnel_quit ();

    pthread_join (hev_thread, NULL);

    pthread_mutex_lock (&hev_mu);
    hev_thread_started = 0;
    free (hev_config);
    hev_config = NULL;
    hev_tun_fd = -1; /* fd 已由 hev 在 fini 中关闭 */
    pthread_mutex_unlock (&hev_mu);
}

/* 最近一次 hev 线程退出码；线程尚在运行返回 -1，从未启动返回 -999 */
int
HevTunnelLastRc (void)
{
    return atomic_load (&hev_last_rc_val);
}

/* hev 线程是否还活着（事件循环仍在跑） */
int
HevTunnelRunning (void)
{
    return atomic_load (&hev_running_flag);
}
