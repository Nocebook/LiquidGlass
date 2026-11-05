#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

// 灵动岛在 iOS 16 的内部名字是 SystemAperture（系统光圈），不是 "Island"。
// 6.1.0-21 一直在找 SBIslandContainerView / SBIslandChromeView / _SBIslandView，
// 这三个类根本不存在（日志里"私有类命中=0"），按类名含 island 的兜底扫描
// 也自然一个都扫不到 —— 这就是点了开关没反应的原因。
//
// 真实承载：SBSystemApertureWindow（灵动岛自己的 UIWindow）。
// 下面这些 _SBSystemAperture* 视图只是窗口内部的内容层，窗口一透明就没意义了，
// 所以只当"信号灯"用，不单独隐藏。
//
// 隐藏手法：把 window 的 alpha 压到 0。不碰 hidden —— 窗口一旦 hidden，
// 系统会认为它"不该存在"并重建，反而更闪。关掉开关立刻还原。
//
// 这里不用 Logos 的 %hook：私有类是否自己实现了 layoutSubviews 无法预判，
// %orig 调到不存在的父实现会直接崩。统一改成"先查再挂"，和 Settings 那边一致。

static NSTimer *gAxsIslandTimer;
static NSMutableSet<UIView *> *gAxsIslandTouched;
static NSMutableDictionary<NSString *, NSValue *> *gAxsIslandOrigIMPs;
static BOOL gAxsIslandDumpedWindows = NO;
static NSInteger gAxsIslandSweepCount = 0;
static NSInteger gAxsIslandHookCount = 0;

static BOOL AxsIslandWanted(void) {
    return [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_hideIsland];
}

static NSMutableSet<UIView *> *AxsIslandTouchedSet(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gAxsIslandTouched = [NSMutableSet set];
    });
    return gAxsIslandTouched;
}

static NSArray<UIView *> *AxsIslandAllWindows(void) {
    NSMutableArray<UIView *> *windows = [NSMutableArray array];
    @try {
        // SpringBoard 不是 UIApplication 子类，[UIApplication sharedApplication] 这里
        // 经常是 nil，所以优先走 UIWindow 的私有类方法拿全量窗口（含内部窗口）。
        Class windowClass = [UIWindow class];
        SEL allSelector = NSSelectorFromString(@"_allWindowsIncludingInternalWindows:onlyVisibleWindows:");
        if ([windowClass respondsToSelector:allSelector]) {
            NSArray *(*call)(id, SEL, BOOL, BOOL) =
                (NSArray *(*)(id, SEL, BOOL, BOOL))[windowClass methodForSelector:allSelector];
            NSArray *list = call(windowClass, allSelector, YES, NO);
            if ([list isKindOfClass:[NSArray class]]) {
                for (id item in list) {
                    if ([item isKindOfClass:[UIView class]]) [windows addObject:(UIView *)item];
                }
            }
        }
    } @catch (NSException *exception) {
        (void)exception;
    }

    if (windows.count == 0) {
        @try {
            UIApplication *application = [UIApplication sharedApplication];
            id list = [application valueForKey:@"windows"];
            if ([list isKindOfClass:[NSArray class]]) {
                for (id item in (NSArray *)list) {
                    if ([item isKindOfClass:[UIView class]]) [windows addObject:(UIView *)item];
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
        } @catch (NSException *exception) {
            (void)exception;
        }
    }
    return windows;
}

/// SystemAperture 是本体的类名；"aperture" 子串能同时覆盖
/// SBSystemApertureWindow 与 _SBSystemAperture* 这些内部视图。
static BOOL AxsIslandNameMatches(NSString *name) {
    if (name.length == 0) return NO;
    return [name rangeOfString:@"aperture" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void AxsIslandApply(UIView *view, BOOL hide) {
    if (!view) return;
    NSMutableSet<UIView *> *touched = AxsIslandTouchedSet();
    if (hide) {
        if (view.alpha != 0.0) {
            view.alpha = 0.0;
            view.userInteractionEnabled = NO;
            [touched addObject:view];
        }
    } else {
        if ([touched containsObject:view]) {
            view.alpha = 1.0;
            view.userInteractionEnabled = YES;
            [touched removeObject:view];
        }
    }
}

static void AxsIslandSweep(void) {
    BOOL hide = AxsIslandWanted();
    NSArray<UIView *> *windows = AxsIslandAllWindows();
    NSInteger matches = 0;

    for (UIView *window in windows) {
        if (AxsIslandNameMatches(NSStringFromClass([window class]))) {
            AxsIslandApply(window, hide);
            matches += 1;
        }
    }

    // 一个都没命中时，把窗口类名打一次日志：出问题能直接看出 16.3 上叫什么。
    if (hide && matches == 0 && !gAxsIslandDumpedWindows && ++gAxsIslandSweepCount >= 3) {
        gAxsIslandDumpedWindows = YES;
        NSMutableString *names = [NSMutableString string];
        for (UIView *window in windows) {
            [names appendFormat:@"%@(%.0f) ", NSStringFromClass([window class]), window.alpha];
        }
        AxsLog(@"灵动岛：未命中 SystemAperture，当前窗口 = %@", names);
    }
}

static void AxsIslandStopTimer(void) {
    if (!gAxsIslandTimer) return;
    [gAxsIslandTimer invalidate];
    gAxsIslandTimer = nil;
}

static void AxsIslandSyncTimer(void) {
    if (AxsIslandWanted()) {
        if (!gAxsIslandTimer) {
            gAxsIslandTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                              repeats:YES
                                                                block:^(NSTimer *timer) {
                (void)timer;
                @try {
                    AxsIslandSweep();
                } @catch (NSException *exception) {
                    (void)exception;
                }
            }];
            gAxsIslandTimer.tolerance = 0.25;
            AxsLog(@"灵动岛：开始守护（1.0s 扫描 SystemAperture）");
        }
        AxsIslandSweep();
    } else {
        BOOL wasRunning = (gAxsIslandTimer != nil);
        AxsIslandStopTimer();
        AxsIslandSweep();  // 还原被我们改过的视图
        if (wasRunning) AxsLog(@"灵动岛：守护停止并还原");
    }
}

// 窗口重建是常态（展开/收起会换宿主），所以 hook 到就立刻处理一次，
// 抓不到也没关系 —— 1s 的扫描兜底。
static void AxsIslandHookBody(id self, SEL _cmd) {
    NSString *key = [NSString stringWithFormat:@"%s:%s",
                     class_getName(object_getClass(self)), sel_getName(_cmd)];
    NSValue *wrapper = gAxsIslandOrigIMPs[key];
    if (wrapper) {
        void (*orig)(id, SEL) = (void (*)(id, SEL))[wrapper pointerValue];
        if (orig) orig(self, _cmd);
    } else {
        // KVO / 运行时换类时 key 对不上，退回父类实现，绝不能吞掉原逻辑。
        Class superclass = class_getSuperclass(object_getClass(self));
        IMP imp = superclass ? class_getMethodImplementation(superclass, _cmd) : NULL;
        if (imp) ((void (*)(id, SEL))imp)(self, _cmd);
    }
    @try {
        UIView *view = (UIView *)self;
        if (AxsIslandNameMatches(NSStringFromClass([view class]))) {
            AxsIslandApply(view, AxsIslandWanted());
        }
    } @catch (NSException *exception) {
        (void)exception;
    }
}

static void AxsIslandHookIfPresent(Class cls, NSString *selectorName) {
    if (!cls) return;
    SEL selector = NSSelectorFromString(selectorName);
    // 只挂类自己实现的版本：继承来的方法一挂就会改到 UIView 上，
    // 等于给全系统所有视图加一层回调。
    if (!axs_liquidglass_classImplements(cls, selector)) return;

    IMP original = class_getMethodImplementation(cls, selector);
    MSHookMessageEx(cls, selector, (IMP)AxsIslandHookBody, &original);
    gAxsIslandOrigIMPs[[NSString stringWithFormat:@"%s:%s", class_getName(cls), sel_getName(selector)]] =
        [NSValue valueWithPointer:(const void *)original];
    gAxsIslandHookCount += 1;
}

__attribute__((constructor))
static void AxsIslandInitialize(void) {
    @autoreleasepool {
        // 只在 SpringBoard 里做，其他进程没有灵动岛。
        NSString *process = [NSProcessInfo processInfo].processName;
        if (![process isEqualToString:@"SpringBoard"]) return;

        gAxsIslandOrigIMPs = [NSMutableDictionary dictionary];

        Class apertureWindow = objc_getClass("SBSystemApertureWindow");
        AxsIslandHookIfPresent(apertureWindow, @"layoutSubviews");
        AxsIslandHookIfPresent(apertureWindow, @"didMoveToWindow");
        AxsIslandHookIfPresent(apertureWindow, @"didMoveToSuperview");

        AxsLog(@"灵动岛：SystemAperture %@，挂钩 %ld 个",
               apertureWindow ? @"存在" : @"不存在", (long)gAxsIslandHookCount);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            AxsIslandSyncTimer();
        });

        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            AxsIslandSyncTimer();
        }];
    }
}
