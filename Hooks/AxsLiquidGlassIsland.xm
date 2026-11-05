#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLog.h"

// 灵动岛在 SpringBoard 里的实现随小版本变化：SBIslandContainerView /
// SBIslandChromeView / _SBIslandView，甚至可能是独立的 island UIWindow。
// 只靠 hook 类方法不够 —— 那些视图是动画期间反复创建销毁的，
// 只在"配置变更"那一刻扫一次，用户点完开关根本等不到下一次机会。
//
// 所以做成两段：
//   1. 类存在就 hook（抓到创建/布局瞬间）
//   2. 开关打开期间跑一个 0.7s 的低频扫描，把漏网的按类名兜住
// 关掉开关时立刻停表并把 hidden 还原，不留后遗症。

static NSTimer *gAxsIslandTimer;
static NSMutableSet<UIView *> *gAxsIslandTouched;

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

static NSArray<UIWindow *> *AxsIslandAllWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    @try {
        UIApplication *application = [UIApplication sharedApplication];
        if (@available(iOS 15.0, *)) {
            for (UIScene *scene in application.connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
            }
        }
        // SpringBoard 的 island window 不一定挂在 connectedScenes 上，KVC 兜一层。
        id extra = [application valueForKey:@"windows"];
        if ([extra isKindOfClass:[NSArray class]]) {
            for (id item in (NSArray *)extra) {
                if ([item isKindOfClass:[UIWindow class]] && ![windows containsObject:item]) {
                    [windows addObject:(UIWindow *)item];
                }
            }
        }
    } @catch (NSException *exception) {
        (void)exception;
    }
    return windows;
}

static BOOL AxsIslandNameMatches(NSString *name) {
    return [name rangeOfString:@"island" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void AxsIslandApply(UIView *view, BOOL hide) {
    if (!view) return;
    NSMutableSet<UIView *> *touched = AxsIslandTouchedSet();
    if (hide) {
        // 用 alpha 而不是 hidden：hidden 会让系统认为这个窗口/视图"不存在"，
        // 灵动岛的展开动画和状态机会跟着乱；alpha 只是视觉消失，布局逻辑不受影响。
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

static void AxsIslandScan(UIView *view, NSInteger depth, BOOL hide) {
    if (!view || depth > 30) return;
    if (AxsIslandNameMatches(NSStringFromClass([view class]))) {
        AxsIslandApply(view, hide);
    }
    // 已经整个隐藏的容器不用再往下钻，省掉大部分遍历开销。
    if (hide && view.alpha == 0.0) return;
    for (UIView *subview in view.subviews) {
        AxsIslandScan(subview, depth + 1, hide);
    }
}

static void AxsIslandSweep(void) {
    BOOL hide = AxsIslandWanted();
    for (UIWindow *window in AxsIslandAllWindows()) {
        if (AxsIslandNameMatches(NSStringFromClass([window class]))) {
            AxsIslandApply(window, hide);
        }
        AxsIslandScan(window, 0, hide);
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
            gAxsIslandTimer = [NSTimer scheduledTimerWithTimeInterval:1.2
                                                              repeats:YES
                                                                block:^(NSTimer *timer) {
                (void)timer;
                @try {
                    AxsIslandSweep();
                } @catch (NSException *exception) {
                    (void)exception;
                }
            }];
            gAxsIslandTimer.tolerance = 0.3;
            AxsLog(@"灵动岛：开始守护（1.2s 扫描）");
        }
        AxsIslandSweep();
    } else {
        BOOL wasRunning = (gAxsIslandTimer != nil);
        AxsIslandStopTimer();
        AxsIslandSweep();  // 还原被我们改过的视图
        if (wasRunning) AxsLog(@"灵动岛：守护停止并还原");
    }
}

// 参数收 id：Logos 生成的 hook 体是 C++ 上下文，直接拿 self 当 UIView* 会匹配失败。
static void AxsIslandHandle(id rawView) {
    @try {
        AxsIslandApply((UIView *)rawView, AxsIslandWanted());
    } @catch (NSException *exception) {
        (void)exception;
    }
}

%group AxsIslandContainerGroup
%hook SBIslandContainerView
- (void)didMoveToWindow {
    %orig;
    AxsIslandHandle(self);
}
- (void)layoutSubviews {
    %orig;
    AxsIslandHandle(self);
}
%end
%end

%group AxsIslandChromeGroup
%hook SBIslandChromeView
- (void)didMoveToWindow {
    %orig;
    AxsIslandHandle(self);
}
- (void)layoutSubviews {
    %orig;
    AxsIslandHandle(self);
}
%end
%end

%group AxsIslandLegacyGroup
%hook _SBIslandView
- (void)didMoveToWindow {
    %orig;
    AxsIslandHandle(self);
}
%end
%end

%ctor {
    @autoreleasepool {
        // 只在 SpringBoard 里做，其他进程没有灵动岛。
        NSString *process = [NSProcessInfo processInfo].processName;
        if (![process isEqualToString:@"SpringBoard"]) return;

        BOOL installed = NO;
        if (objc_getClass("SBIslandContainerView")) {
            %init(AxsIslandContainerGroup);
            installed = YES;
        }
        if (objc_getClass("SBIslandChromeView")) {
            %init(AxsIslandChromeGroup);
            installed = YES;
        }
        if (objc_getClass("_SBIslandView")) {
            %init(AxsIslandLegacyGroup);
            installed = YES;
        }
        AxsLog(@"灵动岛：私有类命中=%d，兜底扫描%s", installed, installed ? "待命" : "启用");

        // 启动后先按当前配置对齐一次；之后每次改配置都重算。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            AxsIslandSyncTimer();
        });

        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            AxsIslandSyncTimer();
        }];
    }
}
