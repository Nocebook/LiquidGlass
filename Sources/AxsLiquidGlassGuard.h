#pragma once

#import <Foundation/Foundation.h>

/// 启动看门狗（7.2.0 新增）。
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

/// 手动解除降级（面板按钮调用，删状态文件）。
void AxsLiquidGlassGuardReset(void);

#ifdef __cplusplus
}
#endif
