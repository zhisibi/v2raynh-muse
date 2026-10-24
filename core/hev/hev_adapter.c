/*
 * v2rayNG Harmony · hev-socks5-tunnel 适配层
 *
 * 导出 NAPI 桥（entry/src/main/cpp/xray_napi.cpp）约定的 C ABI：
 *   int  HevTunnelStart(const char *configYaml, int tunFd);
 *   void HevTunnelStop(void);
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
 * tunFd 所有权：Start 成功后 fd 归 hev 所有（hev 在 fini 时 close），
 * adapter 与 NAPI 侧都不得再 close；Start 失败（线程未起或配置非法）
 * 时 fd 仍归调用方（NAPI 侧负责 close）。
 * 与 Android v2rayNG 的差异：安卓是独立进程 + JNI 传 fd；鸿蒙是同进程
 * 共享库（VpnExtensionAbility 进程内 dlopen）。
 */

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "hev-main.h"

static pthread_mutex_t hev_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_t hev_thread;
static int hev_thread_started = 0;
static int hev_last_rc = -1;
static char *hev_config = NULL;
static int hev_tun_fd = -1;

static void *
hev_thread_main (void *arg)
{
    (void)arg;
    int rc = hev_socks5_tunnel_main_from_str (
        (const unsigned char *)hev_config,
        (unsigned int)strlen (hev_config), hev_tun_fd);
    pthread_mutex_lock (&hev_mu);
    hev_last_rc = rc;
    pthread_mutex_unlock (&hev_mu);
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
    hev_last_rc = -1;
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
