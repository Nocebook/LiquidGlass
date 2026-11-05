#pragma once

#import <Foundation/Foundation.h>

// Logos 的 .xm 会编译成 Objective-C++，这里的 C 函数必须显式 extern "C"，
// 否则调用方按 C++ 规则修饰符号，链接期直接报 undefined symbol。
#ifdef __cplusplus
extern "C" {
#endif

/// 轻量诊断日志。真机调试唯一能拿到的线索：
/// 写 /var/mobile/Library/Caches/com.heli.liquid.log，Filza 直接能看。
/// 只在关键节点写（插件加载、hook 挂载、首次应用效果），不做逐帧输出。
void AxsLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// 日志文件路径，调试面板展示用。
NSString *AxsLogPath(void);

/// 清空日志（面板上的"清空日志"用）。
void AxsLogReset(void);

#ifdef __cplusplus
}
#endif
