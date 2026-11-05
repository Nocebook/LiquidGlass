#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AxsLiquidGlassConfig.h"

// 灵动岛在 SpringBoard 里由 SBIslandContainerView 承载，系统不同小版本还会
// 出现 SBIslandChromeView / _SBIslandView。类名逐个探测，存在才挂 hook，
// 不存在就整组跳过 —— 这样在非灵动岛机型上不会留下空 hook。
//
// 关闭时统一把 alpha 还原成 1，不做"记住原值"，因为灵动岛视图本身常驻 alpha=1，
// 只有系统在展开动画里临时改过它，下一次 layout 就会被系统自己写回来。

static BOOL AxsIslandHidden(void) {
    return [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_hideIsland];
}

// 参数收 id：Logos 生成的 hook 体是 C++ 上下文，把 self（id）显式转成 UIView*
// 会触发重载匹配失败，这里在函数内部转换。
static void AxsIslandApply(id rawView) {
    if (!rawView) return;
    UIView *view = (UIView *)rawView;
    if (![view isKindOfClass:[UIView class]]) return;

    BOOL hide = AxsIslandHidden();
    view.alpha = hide ? 0.0 : 1.0;
    view.userInteractionEnabled = !hide;
}

/// 兜底扫描：类名里带 Island 的视图一律处理，覆盖上面没枚举到的私有类。
static void AxsIslandScanView(UIView *view, NSInteger depth) {
    if (!view || depth > 40) return;
    NSString *name = NSStringFromClass([view class]);
    if ([name rangeOfString:@"Island" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        AxsIslandApply(view);
    }
    for (UIView *subview in view.subviews) {
        AxsIslandScanView(subview, depth + 1);
    }
}

static void AxsIslandScanAllWindows(void) {
    @try {
        UIApplication *application = [UIApplication sharedApplication];
        NSMutableArray<UIWindow *> *windows = [NSMutableArray array];

        // windows 在 iOS 15 起被标记弃用，这里走 windowScene；拿不到再用 KVC 兜底，
        // 避免 -Wdeprecated-declarations 在 -Werror 下直接把构建打断。
        if (@available(iOS 15.0, *)) {
            for (UIScene *scene in application.connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                [windows addObjectsFromArray:windowScene.windows];
            }
        }
        if (windows.count == 0) {
            id value = [application valueForKey:@"windows"];
            if ([value isKindOfClass:[NSArray class]]) {
                for (id item in (NSArray *)value) {
                    if ([item isKindOfClass:[UIWindow class]]) {
                        [windows addObject:item];
                    }
                }
            }
        }

        for (UIWindow *window in windows) {
            AxsIslandScanView(window, 0);
        }
    } @catch (NSException *exception) {
        (void)exception;
    }
}

%group AxsIslandContainerGroup
%hook SBIslandContainerView
- (void)didMoveToWindow {
    %orig;
    @try { AxsIslandApply(self); } @catch (NSException *exception) { (void)exception; }
}
- (void)layoutSubviews {
    %orig;
    @try { AxsIslandApply(self); } @catch (NSException *exception) { (void)exception; }
}
%end
%end

%group AxsIslandChromeGroup
%hook SBIslandChromeView
- (void)didMoveToWindow {
    %orig;
    @try { AxsIslandApply(self); } @catch (NSException *exception) { (void)exception; }
}
- (void)layoutSubviews {
    %orig;
    @try { AxsIslandApply(self); } @catch (NSException *exception) { (void)exception; }
}
%end
%end

%group AxsIslandLegacyGroup
%hook _SBIslandView
- (void)didMoveToWindow {
    %orig;
    @try { AxsIslandApply(self); } @catch (NSException *exception) { (void)exception; }
}
%end
%end

%ctor {
    @autoreleasepool {
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

        // 私类名一个都没命中时，靠窗口扫描兜底，设置改动能立刻看到变化。
        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            AxsIslandScanAllWindows();
        }];

        if (!installed) {
            AxsIslandScanAllWindows();
        }
    }
}
