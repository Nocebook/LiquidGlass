#import "AxsLiquidGlassBackdrop.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

#import <substrate.h>
#import <QuartzCore/QuartzCore.h>

static char kAxsLiquidGlassBackdropAppliedKey;

static void (*axs_liquidglass_origDidMoveToSuperview)(id, SEL);
static void (*axs_liquidglass_origLayoutSubviews)(id, SEL);

static NSInteger gAxsRimAppliedCount = 0;
static NSInteger gAxsRimSkippedCount = 0;
static BOOL gAxsRimLogged = NO;

@interface AxsLiquidGlassBackdrop ()
+ (void)axs_liquidglass_clearRim:(UIView *)view;
@end

static BOOL axs_liquidglass_isWidgetProcess(void) {
    NSString *process = [NSProcessInfo processInfo].processName;
    return [process isEqualToString:@"chronod"] ||
           [process hasPrefix:@"WidgetRenderer"] ||
           [process isEqualToString:@"ClockAngel"];
}

/// 从自身或最近的祖先上找出真实的圆角：系统大量卡片是"父视图裁圆角、
/// 子视图 cornerRadius=0"，只看自己会判成直角，画出来就是四个硬角。
static CGFloat axs_liquidglass_effectiveRadius(UIView *view) {
    if (view.layer.cornerRadius >= 1.0) return view.layer.cornerRadius;
    UIView *current = view.superview;
    for (NSInteger depth = 0; current && depth < 6; depth++) {
        if (current.layer.cornerRadius >= 1.0 && current.layer.masksToBounds) {
            return current.layer.cornerRadius;
        }
        current = current.superview;
    }
    return 0.0;
}

static BOOL axs_liquidglass_isKeyboardSurface(UIView *view) {
    UIView *current = view;
    for (NSInteger depth = 0; current && depth < 12; depth++) {
        NSString *name = NSStringFromClass([current class]).lowercaseString;
        if ([name containsString:@"keyboard"] || [name containsString:@"predictive"]) return YES;
        current = current.superview;
    }
    return NO;
}

static void axs_liquidglass_hookDidMoveToSuperview(id self, SEL _cmd) {
    if (axs_liquidglass_origDidMoveToSuperview) {
        axs_liquidglass_origDidMoveToSuperview(self, _cmd);
    }
    [AxsLiquidGlassBackdrop axs_liquidglass_applyIfNeeded:(UIView *)self];
}

static void axs_liquidglass_hookLayoutSubviews(id self, SEL _cmd) {
    if (axs_liquidglass_origLayoutSubviews) {
        axs_liquidglass_origLayoutSubviews(self, _cmd);
    }
    [AxsLiquidGlassBackdrop axs_liquidglass_applyIfNeeded:(UIView *)self];
}

@implementation AxsLiquidGlassBackdrop

+ (NSHashTable<UIView *> *)axs_liquidglass_registry {
    static NSHashTable<UIView *> *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSHashTable weakObjectsHashTable];
    });
    return registry;
}

+ (void)axs_liquidglass_installHooksIfAvailable {
    Class backdropClass = NSClassFromString(@"_UIBackdropView");
    if (!backdropClass) return;

    // 只挂 _UIBackdropView 自己实现的方法：这里若挂到继承来的方法上，
    // MSHookMessageEx 会改掉 UIView，牵连全系统所有视图。
    if (axs_liquidglass_classImplements(backdropClass, @selector(didMoveToSuperview))) {
        MSHookMessageEx(backdropClass, @selector(didMoveToSuperview),
                        (IMP)axs_liquidglass_hookDidMoveToSuperview,
                        (IMP *)&axs_liquidglass_origDidMoveToSuperview);
    }
    if (axs_liquidglass_classImplements(backdropClass, @selector(layoutSubviews))) {
        MSHookMessageEx(backdropClass, @selector(layoutSubviews),
                        (IMP)axs_liquidglass_hookLayoutSubviews,
                        (IMP *)&axs_liquidglass_origLayoutSubviews);
    }
}

+ (void)axs_liquidglass_applyIfNeeded:(UIView *)view {
    if (!view || ![NSThread isMainThread]) return;
    // 主线已经处理 UIVisualEffectView，这里避免重复设值。
    if ([view isKindOfClass:[UIVisualEffectView class]]) return;
    if (axs_liquidglass_isWidgetProcess()) return;

    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    if (![config axs_liquidglass_isEnabled]) {
        [self axs_liquidglass_clearRim:view];
        return;
    }

    double rim = [config axs_liquidglass_rimStrength];
    if (rim <= 0.01) {
        [self axs_liquidglass_clearRim:view];
        return;
    }
    if (axs_liquidglass_isKeyboardSurface(view) && ![config axs_liquidglass_scopeEnabled:@"keyboard"]) {
        return;
    }

    NSNumber *applied = objc_getAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey);
    if (applied && fabs([applied doubleValue] - rim) < 0.01) return;

    // 6.1.0-21 这里找的是 _UIBackdropView 上的 setBlurRadius: —— 那个 selector
    // 在视图上并不存在（参数在 _UIBackdropViewSettings 上），respondsToSelector
    // 每次都是 NO，于是整条描边路径从来没跑过。模糊改由 Settings 那边统一处理，
    // 这里只负责一件在视图层面一定能做到的事：给玻璃加一圈高光边。
    CGFloat radius = axs_liquidglass_effectiveRadius(view);
    if (radius < 4.0) {
        gAxsRimSkippedCount += 1;
        if (!gAxsRimLogged && gAxsRimSkippedCount >= 40) {
            gAxsRimLogged = YES;
            AxsLog(@"高光：跳过 %ld 个直角表面（累积），已应用 %ld 个",
                   (long)gAxsRimSkippedCount, (long)gAxsRimAppliedCount);
        }
        return;
    }

    @try {
        view.layer.borderWidth = rim * 1.6;
        view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30 + 0.35 * rim].CGColor;
    } @catch (NSException *exception) {
        (void)exception;
    }

    objc_setAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey, @(rim),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self axs_liquidglass_registry] addObject:view];
    gAxsRimAppliedCount += 1;
    if (gAxsRimAppliedCount == 1) {
        AxsLog(@"高光：首次应用 %@（半径 %.1f，线宽 %.2f）",
               NSStringFromClass([view class]), radius, rim * 1.6);
    }
}

+ (void)axs_liquidglass_clearRim:(UIView *)view {
    NSNumber *applied = objc_getAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey);
    if (!applied) return;
    @try {
        view.layer.borderWidth = 0.0;
        view.layer.borderColor = NULL;
    } @catch (NSException *exception) {
        (void)exception;
    }
    objc_setAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)axs_liquidglass_refreshTrackedViews {
    for (UIView *view in [[self axs_liquidglass_registry] allObjects]) {
        objc_setAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self axs_liquidglass_applyIfNeeded:view];
    }
}

@end
