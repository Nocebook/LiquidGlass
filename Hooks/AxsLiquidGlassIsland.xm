#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

// 灵动岛在 iOS 16 的内部名字是 SystemAperture（系统光圈）。
// 真实承载：SBSystemApertureWindow —— 灵动岛自己的 UIWindow，
// 内部的 _SBSystemApertureMagiciansCurtainView 只是"黑色药丸"的填充层。
//
// 6.1.0-26 挂不上的原因：SBSystemApertureWindow 自己既没实现 layoutSubviews，
// 也没实现 didMoveToWindow，class_copyMethodList 全是 0 命中，于是"挂钩 0 个"。
// 这一版改成两条腿走路：
//   1) 直接对 setAlpha:/setHidden: 挂钩 —— 这两个一定继承自 UIView/UIWindow，
//      MSHookMessageEx 会把方法补进子类，orig 取父类实现，不会牵连全局 UIView。
//   2) 1.5s 扫描兜底，抓窗口实例，同时负责关掉开关时的还原。
//
// 隐藏手法：alpha = 0 + hidden = YES。只压 alpha 时某些系统版本仍会画黑色药丸底，
// 只压 hidden 时系统会认为窗口"不该存在"而反复重建；两个一起钉住最稳。

static NSTimer *gAxsIslandTimer;
static __weak UIView *gAxsIslandTarget;
static BOOL gAxsIslandApplied = NO;
static BOOL gAxsIslandDumped = NO;
static NSInteger gAxsIslandSweeps = 0;

static IMP gAxsOrigSetAlpha;
static IMP gAxsOrigSetHidden;
static IMP gAxsOrigLayoutSubviews;
static IMP gAxsOrigDidMoveToWindow;

static BOOL AxsIslandWanted(void) {
    return [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_hideIsland];
}

#pragma mark - 状态写入

/// 全部走 orig IMP，绕开自己的钩子，避免 setAlpha 里再调 setAlpha 无限递归。
static void AxsIslandForceHidden(UIView *view) {
    if (!view) return;
    if (view.alpha != 0.0 && gAxsOrigSetAlpha) {
        ((void (*)(id, SEL, double))gAxsOrigSetAlpha)(view, @selector(setAlpha:), 0.0);
    }
    if (!view.hidden && gAxsOrigSetHidden) {
        ((void (*)(id, SEL, BOOL))gAxsOrigSetHidden)(view, @selector(setHidden:), YES);
    }
}

static void AxsIslandRestore(UIView *view) {
    if (!view) return;
    if (view.hidden && gAxsOrigSetHidden) {
        ((void (*)(id, SEL, BOOL))gAxsOrigSetHidden)(view, @selector(setHidden:), NO);
    }
    if (view.alpha != 1.0 && gAxsOrigSetAlpha) {
        ((void (*)(id, SEL, double))gAxsOrigSetAlpha)(view, @selector(setAlpha:), 1.0);
    }
}

static void AxsIslandRemember(UIView *view) {
    if (!view) return;
    gAxsIslandTarget = view;
    if (!gAxsIslandApplied) {
        gAxsIslandApplied = YES;
        AxsLog(@"灵动岛：已隐藏 %@（%dx%d）", NSStringFromClass([view class]),
               (int)CGRectGetWidth(view.bounds), (int)CGRectGetHeight(view.bounds));
    }
}

#pragma mark - 窗口枚举

static void AxsIslandCollectWindows(NSMutableArray<UIView *> *windows) {
    if (!windows) return;
    @try {
        // SpringBoard 不是 UIApplication 子类，优先走 UIWindow 的私有类方法拿全量窗口
        // （含系统内部窗口），只靠 connectedScenes 会漏掉灵动岛所在的那一个。
        Class windowClass = [UIWindow class];
        SEL allSelector = NSSelectorFromString(@"_allWindowsIncludingInternalWindows:onlyVisibleWindows:");
        if ([windowClass respondsToSelector:allSelector]) {
            NSArray *(*call)(id, SEL, BOOL, BOOL) =
                (NSArray *(*)(id, SEL, BOOL, BOOL))[windowClass methodForSelector:allSelector];
            NSArray *list = call(windowClass, allSelector, YES, NO);
            if ([list isKindOfClass:[NSArray class]]) {
                for (id item in list) {
                    if ([item isKindOfClass:[UIView class]] && ![windows containsObject:item]) {
                        [windows addObject:(UIView *)item];
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        (void)exception;
    }

    @try {
        UIApplication *application = [UIApplication sharedApplication];
        if (application) {
            id list = [application valueForKey:@"windows"];
            if ([list isKindOfClass:[NSArray class]]) {
                for (id item in (NSArray *)list) {
                    if ([item isKindOfClass:[UIView class]] && ![windows containsObject:item]) {
                        [windows addObject:(UIView *)item];
                    }
                }
            }
            if (@available(iOS 15.0, *)) {
                for (UIScene *scene in application.connectedScenes) {
                    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                        if (![windows containsObject:window]) [windows addObject:window];
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        (void)exception;
    }
}

static BOOL AxsIslandNameMatches(NSString *name) {
    if (name.length == 0) return NO;
    return [name rangeOfString:@"aperture" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

/// 窗口里再往下捞一层：某些版本灵动岛主体不挂在窗口上，而是一个
/// _SBSystemApertureContainerView / MagiciansCurtainView。命中就返回最外层那个。
static UIView *AxsIslandFindInView(UIView *root, NSInteger depth) {
    if (!root || depth > 6) return nil;
    if (AxsIslandNameMatches(NSStringFromClass([root class]))) return root;
    for (UIView *child in root.subviews) {
        UIView *found = AxsIslandFindInView(child, depth + 1);
        if (found) return found;
    }
    return nil;
}

#pragma mark - 扫描

static void AxsIslandSweep(void) {
    BOOL hide = AxsIslandWanted();
    gAxsIslandSweeps += 1;

    NSMutableArray<UIView *> *windows = [NSMutableArray array];
    AxsIslandCollectWindows(windows);

    UIView *matched = nil;
    for (UIView *window in windows) {
        if (AxsIslandNameMatches(NSStringFromClass([window class]))) {
            matched = window;
            break;
        }
    }
    if (!matched) {
        // 窗口名不匹配时再往下找一层，但只认视图类名，别把整个 keyWindow 当成灵动岛。
        for (UIView *window in windows) {
            UIView *found = AxsIslandFindInView(window, 0);
            if (found && found != window) {
                matched = found;
                break;
            }
        }
    }

    if (matched) {
        if (hide) {
            AxsIslandForceHidden(matched);
            AxsIslandRemember(matched);
        } else {
            AxsIslandRestore(matched);
            if (gAxsIslandApplied) {
                gAxsIslandApplied = NO;
                AxsLog(@"灵动岛：已还原 %@", NSStringFromClass([matched class]));
            }
        }
        return;
    }

    // 抓不到窗口时，把窗口清单打一次：下次出问题能直接看 16.3 上叫什么名字。
    if (hide && !gAxsIslandDumped && gAxsIslandSweeps >= 2) {
        gAxsIslandDumped = YES;
        NSMutableString *names = [NSMutableString string];
        NSInteger limit = MIN((NSInteger)windows.count, 14);
        for (NSInteger index = 0; index < limit; index++) {
            UIView *window = windows[(NSUInteger)index];
            [names appendFormat:@"%@(%.0f)%@ ", NSStringFromClass([window class]), window.alpha,
                                 window.hidden ? @"[H]" : @""];
        }
        AxsLog(@"灵动岛：未命中，窗口 %ld 个 = %@", (long)windows.count, names);
    }

    // 已经钉住的那个实例也顺手补一刀：系统可能在别处把 alpha 抬回去。
    if (hide && gAxsIslandTarget) AxsIslandForceHidden(gAxsIslandTarget);
}

#pragma mark - 钩子

// 一律不判断"类自己有没有实现"：这两个方法必然继承自 UIView，
// MSHookMessageEx 会把实现补进 SBSystemApertureWindow 这一层，不影响其它视图。
static IMP AxsIslandInstall(Class cls, SEL selector, IMP replacement) {
    if (!cls || !selector) return NULL;
    IMP original = class_getMethodImplementation(cls, selector);
    IMP hooked = NULL;
    MSHookMessageEx(cls, selector, replacement, &hooked);
    // 挂失败时退回挂之前的实现，至少不会把窗口的正常 alpha/hidden 行为弄丢。
    return hooked ?: original;
}

static void AxsIslandHookSetAlpha(id self, SEL _cmd, double alpha) {
    if (AxsIslandWanted()) {
        AxsIslandRemember((UIView *)self);
        if (gAxsOrigSetAlpha) ((void (*)(id, SEL, double))gAxsOrigSetAlpha)(self, _cmd, 0.0);
        return;
    }
    if (gAxsOrigSetAlpha) ((void (*)(id, SEL, double))gAxsOrigSetAlpha)(self, _cmd, alpha);
}

static void AxsIslandHookSetHidden(id self, SEL _cmd, BOOL hidden) {
    if (AxsIslandWanted()) {
        AxsIslandRemember((UIView *)self);
        if (gAxsOrigSetHidden) ((void (*)(id, SEL, BOOL))gAxsOrigSetHidden)(self, _cmd, YES);
        return;
    }
    if (gAxsOrigSetHidden) ((void (*)(id, SEL, BOOL))gAxsOrigSetHidden)(self, _cmd, hidden);
}

static void AxsIslandHookLayout(id self, SEL _cmd) {
    if (gAxsOrigLayoutSubviews) ((void (*)(id, SEL))gAxsOrigLayoutSubviews)(self, _cmd);
    if (AxsIslandWanted() && gAxsOrigSetAlpha) {
        AxsIslandRemember((UIView *)self);
        ((void (*)(id, SEL, double))gAxsOrigSetAlpha)(self, @selector(setAlpha:), 0.0);
    }
}

static void AxsIslandHookMoved(id self, SEL _cmd) {
    if (gAxsOrigDidMoveToWindow) ((void (*)(id, SEL))gAxsOrigDidMoveToWindow)(self, _cmd);
    if (AxsIslandWanted()) {
        AxsIslandRemember((UIView *)self);
        AxsIslandForceHidden((UIView *)self);
    }
}

#pragma mark - 定时器

static void AxsIslandStopTimer(void) {
    if (!gAxsIslandTimer) return;
    [gAxsIslandTimer invalidate];
    gAxsIslandTimer = nil;
}

static void AxsIslandSync(void) {
    if (AxsIslandWanted()) {
        if (!gAxsIslandTimer) {
            // 1.5s 只是兜底：绝大多数状态变化都会走上面的 setAlpha/setHidden 钩子。
            gAxsIslandTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                              repeats:YES
                                                                block:^(NSTimer *timer) {
                (void)timer;
                @try {
                    AxsIslandSweep();
                } @catch (NSException *exception) {
                    (void)exception;
                }
            }];
            gAxsIslandTimer.tolerance = 0.6;
            AxsLog(@"灵动岛：开始守护（1.5s 兜底扫描）");
        }
        AxsIslandSweep();
    } else {
        BOOL wasRunning = (gAxsIslandTimer != nil);
        AxsIslandStopTimer();
        AxsIslandSweep();
        if (wasRunning) AxsLog(@"灵动岛：守护停止");
    }
}

__attribute__((constructor))
static void AxsIslandInitialize(void) {
    @autoreleasepool {
        NSString *process = [NSProcessInfo processInfo].processName;
        if (![process isEqualToString:@"SpringBoard"]) return;

        Class apertureWindow = objc_getClass("SBSystemApertureWindow");
        if (apertureWindow) {
            gAxsOrigSetAlpha = AxsIslandInstall(apertureWindow, @selector(setAlpha:),
                                                (IMP)AxsIslandHookSetAlpha);
            gAxsOrigSetHidden = AxsIslandInstall(apertureWindow, @selector(setHidden:),
                                                 (IMP)AxsIslandHookSetHidden);
            gAxsOrigLayoutSubviews = AxsIslandInstall(apertureWindow, @selector(layoutSubviews),
                                                      (IMP)AxsIslandHookLayout);
            gAxsOrigDidMoveToWindow = AxsIslandInstall(apertureWindow, @selector(didMoveToWindow),
                                                       (IMP)AxsIslandHookMoved);
        }

        // 兜底路径也要能改 alpha/hidden，类拿不到时用 UIView 的实现。
        if (!gAxsOrigSetAlpha) {
            gAxsOrigSetAlpha = class_getMethodImplementation([UIView class], @selector(setAlpha:));
        }
        if (!gAxsOrigSetHidden) {
            gAxsOrigSetHidden = class_getMethodImplementation([UIView class], @selector(setHidden:));
        }

        AxsLog(@"灵动岛：SystemAperture %@，挂钩 alpha=%d hidden=%d",
               apertureWindow ? @"存在" : @"不存在",
               gAxsOrigSetAlpha != NULL, gAxsOrigSetHidden != NULL);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            AxsIslandSync();
        });

        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            AxsIslandSync();
        }];
    }
}
