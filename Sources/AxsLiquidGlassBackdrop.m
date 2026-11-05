#import "AxsLiquidGlassBackdrop.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassPrivate.h"

#import <substrate.h>

static char kAxsLiquidGlassBackdropAppliedKey;

static void (*axs_liquidglass_origDidMoveToSuperview)(id, SEL);
static void (*axs_liquidglass_origLayoutSubviews)(id, SEL);

// _UIBackdropView 是 UIView 子类，但没有 UIVisualEffectView 那套 effect 接口。
// 它内部自己画 CABackdropLayer，所以只能改参数，绝不能往里插子视图或子层。
static BOOL axs_liquidglass_isDesktopSurface(UIView *view) {
    UIView *current = view;
    for (NSInteger depth = 0; current && depth < 16; depth++) {
        NSString *name = NSStringFromClass([current class]).lowercaseString;
        if ([name containsString:@"dock"] || [name containsString:@"folder"] ||
            [name containsString:@"homescreen"] || [name containsString:@"iconlist"]) {
            return YES;
        }
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
    if (!axs_liquidglass_isDesktopSurface(view)) return;

    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    if (![config axs_liquidglass_isEnabled]) return;
    if (![config axs_liquidglass_scopeEnabled:@"home"]) return;

    double radius = [config axs_liquidglass_blurRadius];
    NSNumber *applied = objc_getAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey);
    if (applied && fabs([applied doubleValue] - radius) < 0.01) return;

    // 16.x 的 _UIBackdropView 是否还认 setBlurRadius: 由 respondsToSelector 决定；
    // 不认就整个跳过，不要退化成 KVC 硬写，避免触发内部 KVO 重排。
    SEL radiusSelector = NSSelectorFromString(@"setBlurRadius:");
    if (!radiusSelector || ![view respondsToSelector:radiusSelector]) return;

    AxsLiquidGlassSetNumber(view, @"setBlurRadius:", @"blurRadius", radius);
    AxsLiquidGlassSetNumber(view, @"setSaturationDeltaFactor:", @"saturationDeltaFactor",
                            [config axs_liquidglass_saturation]);

    objc_setAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey, @(radius),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self axs_liquidglass_registry] addObject:view];
}

+ (void)axs_liquidglass_refreshTrackedViews {
    for (UIView *view in [[self axs_liquidglass_registry] allObjects]) {
        objc_setAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self axs_liquidglass_applyIfNeeded:view];
    }
}

@end
