#pragma once

#import <Foundation/Foundation.h>

/// 灵动岛模块的入口（实现在 Hooks/AxsLiquidGlassIsland.xm）。
///
/// 7.3.0 起它**不再**是一个 __attribute__((constructor))。
/// 那正是 7.2.0 里唯一一处绕过看门狗的代码：等级已经降到 2（"一个 Hook 都不装"），
/// 这个构造函数照样在启动后 1 秒跑起来去扫窗口树、还顺手把配置单例拉起来，
/// 于是一个已经"停用"的插件仍然每次开机都崩 —— 用户看到的永远是安全模式。
///
/// 现在改成：由 %ctor 在启动稳定窗口（8 秒）之后主动调用一次，
/// 调用前先过看门狗与开关两道门。默认开关是关的，所以默认路径里
/// 根本没有灵动岛代码在跑。
#ifdef __cplusplus
extern "C" {
#endif

/// 按当前状态决定是否启动灵动岛守护。开关关 / 保护中 / 非 SpringBoard 时直接返回。
void AxsLiquidGlassIslandStartIfWanted(void);

/// 配置变更时重算一次（面板改了开关后调用）。
void AxsLiquidGlassIslandResync(void);

#ifdef __cplusplus
}
#endif
