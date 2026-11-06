#pragma once

#import <Foundation/Foundation.h>

/// 启动看门狗（7.2.0 引入，7.3.0 重写）。
///
/// 越狱插件最难受的失败形态不是"没效果"，而是"装完直接安全模式"：
/// 用户既进不了桌面，也打不开设置面板，连日志都看不到，只能卸载重来。
///
/// 这里用一个落盘的心跳把这条路堵死：
///   1. SpringBoard 每次启动先写一条"开始"，成功跑满 20 秒后改写"稳定"；
///   2. 下次启动时如果发现上一条还是"开始"，说明上一次是崩在启动阶段的，
///      记一次异常启动，并把效果降一级；
///   3. 等级 1 = 只保留模糊参数改写（去掉玻璃膜、描边、折射、灵动岛），
///      等级 2 = 一个 Hook 都不装，等于没装插件；
///   4. 等级一旦升上去就保持，不会自己震荡 —— 用户能正常用手机，
///      日志里能看到降级原因，面板里有按钮可以手动恢复。
///
/// 7.3.0 的两处关键修正（7.2.0 正是栽在这两处）：
///
///   a) **存储介质换成 CFPreferences**。7.2.0 用 fopen 直接写
///      /var/mobile/Library/Caches —— SpringBoard 的沙盒很可能直接拒绝，
///      写失败 → 等级永远是 0 → 下次启动照样全量加载 → 无限崩溃循环，
///      用户看到的就是"怎么装都是安全模式"。CFPreferences 的落盘由
///      cfprefsd 代劳，沙盒进程也能写，这条路才是通的。
///
///   b) **装饰层与启动解耦**。等级只决定"装不装 Hook"，而"往系统图层树里
///      插图层"这件事另外再加一道时间闸门（decorReady）：SpringBoard 启动后
///      前 8 秒一律只改模糊参数，不碰任何图层。安全模式的判定窗口就在启动后
///      这几秒里，把风险最高的动作用时间错开，等于直接把这条路堵死。
///
/// 换版本会把等级重置回 0，所以每次发新版都给一次"干净启动"的机会。
/// 注意：只有 SpringBoard 参与这套判定，其他注入进程直接返回 0。
///
/// 这几个函数被 Hooks 里的 .xm 调用，而 .xm 由 Logos 以 Objective-C++ 编译 ——
/// 少了这层 extern "C"，它们会被当成 C++ 符号（__Z28AxsLiquidGlassGuard...），
/// 与 Guard.m 里的 C 符号对不上，链接期直接 undefined。
#ifdef __cplusplus
extern "C" {
#endif

NSInteger AxsLiquidGlassGuardBeginLaunch(void);

/// 当前降级等级：0 正常 / 1 只保留模糊 / 2 完全停用。
NSInteger AxsLiquidGlassGuardLevel(void);

/// 记录"走到哪一步了"。崩在哪个阶段，下次读文件就能看到。
void AxsLiquidGlassGuardNoteStage(NSString *stage);

/// 装完 Hook 后调用：20 秒后打一次"稳定"心跳。
void AxsLiquidGlassGuardScheduleHeartbeat(void);

/// 装饰层（玻璃膜 / 锥形描边 / 折射网格 / 灵动岛）现在能不能动手。
///
/// 只有在"等级 0"且"已经过了启动稳定窗口"时才返回 YES。
/// 所有会往系统图层树里插图层的调用点都必须先问这一句：
/// 这些动作一旦在启动瞬间触发，就是 SpringBoard 直接死 = 安全模式。
BOOL AxsLiquidGlassGuardDecorReady(void);

/// 启动稳定窗口结束，放开装饰层。由 %ctor 里的一次性延迟任务调用。
void AxsLiquidGlassGuardMarkDecorReady(void);

/// 手动解除降级（面板按钮调用，清掉状态）。
void AxsLiquidGlassGuardReset(void);

/// 面板用的状态描述（"等级 0 · 正常" 之类），没有记录时返回 nil。
NSString *AxsLiquidGlassGuardStatusText(void);

#ifdef __cplusplus
}
#endif
