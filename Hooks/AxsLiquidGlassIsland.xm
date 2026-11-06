#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassIslandDriver.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

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
// 只在 SpringBoard 里跑，只在有容器时动，容器消失即自动失效。

static NSTimer *gAxsIslandTimer;
static __weak UIView *gAxsIslandHiddenTarget;
static BOOL gAxsIslandHidden = NO;
static BOOL gAxsIslandDumped = NO;
static NSInteger gAxsIslandSweeps = 0;
static NSInteger gAxsIslandMisses = 0;
static BOOL gAxsIslandEventDriven = NO;

static BOOL AxsIslandHideWanted(void) {
    return [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_hideIsland];
}

static BOOL AxsIslandGlassWanted(void) {
    return [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_islandGlass];
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
    UIView *container = [AxsLiquidGlassIslandDriver axs_liquidglass_islandContainer];

    if (!container) {
        gAxsIslandMisses += 1;
        if ((hide || AxsIslandGlassWanted()) && !gAxsIslandDumped && gAxsIslandSweeps >= 3) {
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
        } else {
            // 隐藏状态已经稳定，剩下的只是"系统会不会重建容器"，
            // 没必要再按 1.2 秒的频率盯着 —— 退到兜底节奏。
            gAxsIslandEventDriven = YES;
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

    if (AxsIslandGlassWanted()) {
        [AxsLiquidGlassIslandDriver axs_liquidglass_islandRefresh];
        // 容器类的 layoutSubviews 一旦被接管，尺寸变化就是事件驱动的，
        // 轮询只剩"系统重建容器"这一种兜底场景，可以退到 2.5 秒。
        gAxsIslandEventDriven = [AxsLiquidGlassIslandDriver axs_liquidglass_islandIsEventDriven];
    } else {
        [AxsLiquidGlassIslandDriver axs_liquidglass_islandTeardown];
    }
}

#pragma mark - 定时器

/// 下一轮扫描间隔。
/// 旧版是固定 1.2 秒的 repeating timer：只要灵动岛玻璃开着，SpringBoard 就永远
/// 每 1.2 秒醒一次扫全窗口树，设备再也进不了深睡 —— 这是装完插件待机掉电快的主因。
/// 现在按"有没有事情可做"分三档：事件驱动 → 2.5s 兜底；未接管 → 1.2s 保效果；
/// 长时间找不到容器（锁屏、刚重启）→ 6s 慢速等待。
static NSTimeInterval AxsIslandNextInterval(void) {
    if (gAxsIslandMisses >= 3) return 6.0;
    if (gAxsIslandEventDriven) return 2.5;
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
            (void)exception;
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

__attribute__((constructor))
static void AxsIslandInitialize(void) {
    @autoreleasepool {
        NSString *process = [NSProcessInfo processInfo].processName;
        if (![process isEqualToString:@"SpringBoard"]) return;

        AxsLog(@"灵动岛：SystemAperture %@",
               objc_getClass("SBSystemApertureWindow") ? @"存在" : @"不存在");

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            AxsIslandSync();
        });

        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            AxsIslandSync();
        }];
    }
}
