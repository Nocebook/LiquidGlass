#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassGuard.h"
#import "AxsLiquidGlassIslandBridge.h"
#import "AxsLiquidGlassIslandDriver.h"
#import "AxsLiquidGlassLog.h"

// 灵动岛（iOS 16 内部名 SystemAperture）这一版彻底换思路。
//
// 旧版对 SBSystemApertureWindow 挂 setAlpha:/setHidden: —— 但窗口类自己并不实现这些方法，
// 而且真正的药丸背景根本不在窗口直接子视图里，而是一个由 driver 托管的容器
// （对应 Liquidify 的 CCSystemApertureBackgroundDriver initWithContainerView:）。
// 所以旧版"挂钩 0 个"、开关点了没反应。
//
// 这一版两条链路都挂在**容器**上：
//   1) 玻璃：交给 AxsLiquidGlassIslandDriver，挂玻璃膜 + 边缘折射；
//   2) 隐藏：直接把容器 alpha 压 0 + hidden，不动窗口，系统不会反复重建。
//
// 7.3.0 起这里不再是 __attribute__((constructor))，也不再默认启用。
// 原因写得很清楚，别再改回去：
//   - 构造函数的执行时机比 %ctor 更早，看门狗还没做判定就已经在跑；
//   - 它在启动后 1 秒就去扫窗口树、往系统托管的容器里插图层，
//     正好落在"安全模式判定窗口"里；
//   - 于是 7.2.0 的等级 2（号称不装任何 Hook）形同虚设 —— 插件"停用"了还在崩。
// 现在只由 %ctor 在启动稳定窗口之后调 AxsLiquidGlassIslandStartIfWanted()。

static NSTimer *gAxsIslandTimer;
static __weak UIView *gAxsIslandHiddenTarget;
static BOOL gAxsIslandHidden = NO;
static BOOL gAxsIslandDumped = NO;
static NSInteger gAxsIslandSweeps = 0;
static NSInteger gAxsIslandMisses = 0;
static BOOL gAxsIslandHandlerInstalled = NO;
static BOOL gAxsIslandEverWanted = NO;

/// 读结构体快照而不是走消息派发：这一句在每一轮扫描里都要问一次，
/// 而且配置层已经把"看门狗等级 1 时全部归零"算进快照了，这里不必再判断。
static BOOL AxsIslandHideWanted(void) {
    return AxsLiquidGlassParamsGet()->hideIsland;
}

static BOOL AxsIslandGlassWanted(void) {
    return AxsLiquidGlassParamsGet()->islandGlass;
}

static void AxsIslandSetHiddenState(UIView *view, BOOL hidden) {
    if (!view) return;
    view.alpha = hidden ? 0.0 : 1.0;
    view.hidden = hidden;
}

#pragma mark - 扫描

static void AxsIslandSweep(void) {
    gAxsIslandSweeps += 1;

    BOOL hide = AxsIslandHideWanted();
    BOOL glass = AxsIslandGlassWanted();

    // 两个开关都关了（或者看门狗刚把参数归零）：不扫窗口树，摘干净就收工。
    if (!hide && !glass) {
        [AxsLiquidGlassIslandDriver axs_liquidglass_islandTeardown];
        if (gAxsIslandHiddenTarget) {
            AxsIslandSetHiddenState(gAxsIslandHiddenTarget, NO);
            gAxsIslandHiddenTarget = nil;
            gAxsIslandHidden = NO;
        }
        gAxsIslandMisses += 1;
        return;
    }

    // 装饰层闸门没开（启动后的前 8 秒，或保护等级不为 0）时，连窗口树都不扫。
    // 这一步是 7.3.0 的关键：把"往系统容器里插图层"这件事推到安全模式判定窗口之后。
    if (!AxsLiquidGlassGuardDecorReady()) {
        gAxsIslandMisses += 1;
        return;
    }

    UIView *container = [AxsLiquidGlassIslandDriver axs_liquidglass_islandContainer];

    if (!container) {
        gAxsIslandMisses += 1;
        if ((hide || glass) && !gAxsIslandDumped && gAxsIslandSweeps >= 3) {
            gAxsIslandDumped = YES;
            NSArray<UIView *> *windows = [AxsLiquidGlassIslandDriver axs_liquidglass_islandWindows];
            NSMutableString *names = [NSMutableString string];
            NSInteger limit = MIN((NSInteger)windows.count, 12);
            for (NSInteger index = 0; index < limit; index++) {
                UIView *window = windows[(NSUInteger)index];
                [names appendFormat:@"%@(%.0fx%.0f) ", NSStringFromClass([window class]),
                                     CGRectGetWidth(window.bounds), CGRectGetHeight(window.bounds)];
            }
            AxsLog(@"灵动岛：未命中容器，窗口 %ld 个 = %@", (long)windows.count, names);
        }
        return;
    }
    gAxsIslandMisses = 0;

    // 隐藏优先：玻璃在不可见时没有意义，先摘掉省一笔合成开销。
    if (hide) {
        [AxsLiquidGlassIslandDriver axs_liquidglass_islandTeardown];
        if (gAxsIslandHiddenTarget != container) gAxsIslandHiddenTarget = container;
        AxsIslandSetHiddenState(container, YES);
        if (!gAxsIslandHidden) {
            gAxsIslandHidden = YES;
            AxsLog(@"灵动岛：已隐藏 %@（%.0fx%.0f）", NSStringFromClass([container class]),
                   CGRectGetWidth(container.bounds), CGRectGetHeight(container.bounds));
        }
        return;
    }

    if (gAxsIslandHiddenTarget) {
        AxsIslandSetHiddenState(gAxsIslandHiddenTarget, NO);
        if (gAxsIslandHidden) {
            gAxsIslandHidden = NO;
            AxsLog(@"灵动岛：已还原 %@", NSStringFromClass([gAxsIslandHiddenTarget class]));
        }
        gAxsIslandHiddenTarget = nil;
    }

    if (glass) {
        [AxsLiquidGlassIslandDriver axs_liquidglass_islandRefresh];
    } else {
        [AxsLiquidGlassIslandDriver axs_liquidglass_islandTeardown];
    }
}

#pragma mark - 定时器

/// 下一轮扫描间隔。
/// 旧版是固定 1.2 秒的 repeating timer：只要灵动岛玻璃开着，SpringBoard 就永远
/// 每 1.2 秒醒一次扫全窗口树，设备再也进不了深睡 —— 这是装完插件待机掉电快的主因。
/// 现在按"有没有事情可做"分三档：玻璃已挂稳 → 2.0s；还没挂上 → 1.2s；
/// 长时间找不到容器（锁屏、刚重启）→ 6s 慢速等待。
/// 挂稳之后的一轮扫描只有几次浮点比较（几何签名没变就直接返回），2 秒一次可以忽略。
static NSTimeInterval AxsIslandNextInterval(void) {
    if (gAxsIslandMisses >= 3) return 6.0;
    if ([AxsLiquidGlassIslandDriver axs_liquidglass_islandIsMounted]) return 2.0;
    return 1.2;
}

static void AxsIslandStopTimer(void) {
    if (!gAxsIslandTimer) return;
    [gAxsIslandTimer invalidate];
    gAxsIslandTimer = nil;
}

static void AxsIslandScheduleNext(void) {
    AxsIslandStopTimer();
    NSTimeInterval interval = AxsIslandNextInterval();
    gAxsIslandTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                      repeats:NO
                                                        block:^(NSTimer *timer) {
        (void)timer;
        gAxsIslandTimer = nil;
        @try {
            AxsIslandSweep();
        } @catch (NSException *exception) {
            // 这里必须真正接住：抛到 SpringBoard 的 runloop 里就是一次进程崩溃。
            AxsLog(@"灵动岛：扫描异常已拦截（%@）", exception.reason);
        }
        AxsIslandScheduleNext();
    }];
    // 允许系统把这次唤醒合并到别的唤醒里，进一步省电。
    gAxsIslandTimer.tolerance = interval * 0.4;
}

static void AxsIslandSync(void) {
    // 开关全关时不需要守护线程，扫一次退出即可（同时负责把已生效的状态还回去）。
    if (!AxsIslandHideWanted() && !AxsIslandGlassWanted()) {
        BOOL wasRunning = (gAxsIslandTimer != nil);
        AxsIslandStopTimer();
        AxsIslandSweep();
        if (wasRunning) AxsLog(@"灵动岛：守护停止");
        return;
    }

    AxsIslandSweep();
    AxsIslandScheduleNext();
    AxsLog(@"灵动岛：开始守护（%.1fs 自适应扫描）", AxsIslandNextInterval());
}

#pragma mark - 入口

void AxsLiquidGlassIslandStartIfWanted(void) {
    @try {
        if (![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"]) return;

        // 第一道门：看门狗。等级 >= 1 说明上次启动崩过，这一块完全不参与。
        if (AxsLiquidGlassGuardLevel() >= 1) {
            AxsLog(@"灵动岛：启动保护中（等级 %ld），本次不启用",
                   (long)AxsLiquidGlassGuardLevel());
            return;
        }

        // 第二道门：装饰层闸门。启动稳定窗口没过就在这里停下。
        if (!AxsLiquidGlassGuardDecorReady()) {
            AxsLog(@"灵动岛：稳定窗口未结束，暂不启用");
            return;
        }

        if (!AxsIslandHandlerInstalled) {
            AxsIslandHandlerInstalled = YES;
            [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
                @try {
                    AxsIslandSync();
                } @catch (NSException *exception) {
                    AxsLog(@"灵动岛：重载异常已拦截（%@）", exception.reason);
                }
            }];
        }

        // 第三道门：用户开关。默认全关 —— 这一块从未在你的机器上验证过，
        // 默认打开等于拿"能不能开机"去赌一个没验证过的东西。
        if (!AxsIslandHideWanted() && !AxsIslandGlassWanted()) {
            if (!gAxsIslandEverWanted) {
                gAxsIslandEverWanted = YES;
                AxsLog(@"灵动岛：两个开关都是关的，守护不启动（省电）");
            }
            return;
        }
        gAxsIslandEverWanted = YES;

        AxsLog(@"灵动岛：SystemAperture %@",
               objc_getClass("SBSystemApertureWindow") ? @"存在" : @"不存在");
        AxsIslandSync();
    } @catch (NSException *exception) {
        AxsLog(@"灵动岛：启动异常已拦截（%@）", exception.reason);
    }
}

void AxsLiquidGlassIslandResync(void) {
    AxsLiquidGlassIslandStartIfWanted();
}
