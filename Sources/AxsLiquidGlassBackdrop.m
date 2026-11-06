#import "AxsLiquidGlassBackdrop.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLens.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassMesh.h"
#import "AxsLiquidGlassPrivate.h"
#import "AxsLiquidGlassSurface.h"

#import <substrate.h>
#import <QuartzCore/QuartzCore.h>

static char kAxsLiquidGlassBackdropAppliedKey;

static void (*axs_liquidglass_origDidMoveToSuperview)(id, SEL);
static void (*axs_liquidglass_origLayoutSubviews)(id, SEL);

static NSInteger gAxsBackdropAppliedCount = 0;
static NSInteger gAxsBackdropSkippedCount = 0;
static BOOL gAxsBackdropLogged = NO;

@interface AxsLiquidGlassBackdrop ()
+ (void)axs_liquidglass_clear:(UIView *)view;
@end

static BOOL axs_liquidglass_isWidgetProcess(void) {
    NSString *process = [NSProcessInfo processInfo].processName;
    return [process isEqualToString:@"chronod"] ||
           [process hasPrefix:@"WidgetRenderer"] ||
           [process isEqualToString:@"ClockAngel"];
}

/// 从自身或最近的祖先上找出真实的圆角：系统大量卡片是"父视图裁圆角、
/// 子视图 cornerRadius=0"，只看自己会判成直角，玻璃膜和折射网格都会画歪。
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
    // 主线已经处理 UIVisualEffectView，这里避免重复处理。
    // UIVisualEffectView 内部那个 _UIVisualEffectBackdropView 本身就是 _UIBackdropView 子类，
    // 不挡掉就会同一块玻璃被贴两遍膜（既费电又发白）。
    if ([view isKindOfClass:[UIVisualEffectView class]]) return;
    UIView *ancestor = view.superview;
    for (NSInteger depth = 0; ancestor && depth < 3; depth++) {
        if ([ancestor isKindOfClass:[UIVisualEffectView class]]) return;
        ancestor = ancestor.superview;
    }
    if (axs_liquidglass_isWidgetProcess()) return;

    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    if (![config axs_liquidglass_isEnabled]) {
        [self axs_liquidglass_clear:view];
        return;
    }

    double rim = [config axs_liquidglass_rimStrength];
    double fill = [config axs_liquidglass_fillAlpha];
    double specular = [config axs_liquidglass_specularStrength];
    double mesh = [config axs_liquidglass_meshStrength];
    NSInteger perfMode = [config axs_liquidglass_perfMode];

    if (rim <= 0.001 && fill <= 0.001 && specular <= 0.001) {
        [self axs_liquidglass_clear:view];
        return;
    }
    if (axs_liquidglass_isKeyboardSurface(view) && ![config axs_liquidglass_scopeEnabled:@"keyboard"]) {
        return;
    }

    // 签名比对：布局回调非常频繁，参数没变就直接返回，避免每帧重建图层。
    NSString *signature = [NSString stringWithFormat:@"%.1f|%.1f|%.1f|%.1f|%.1f|%ld",
                           rim, fill, specular, mesh, axs_liquidglass_effectiveRadius(view),
                           (long)perfMode];
    NSString *previous = objc_getAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey);
    if ([previous isEqualToString:signature]) {
        [AxsLiquidGlassLens axs_liquidglass_layoutView:view radius:axs_liquidglass_effectiveRadius(view)];
        return;
    }

    CGFloat radius = axs_liquidglass_effectiveRadius(view);
    if (radius < 4.0) {
        // 直角表面不加描边，否则会在方角上画出一圈硬边。
        gAxsBackdropSkippedCount += 1;
        if (!gAxsBackdropLogged && gAxsBackdropSkippedCount >= 40) {
            gAxsBackdropLogged = YES;
            AxsLog(@"玻璃膜：跳过 %ld 个直角表面（累积），已应用 %ld 个",
                   (long)gAxsBackdropSkippedCount, (long)gAxsBackdropAppliedCount);
        }
        return;
    }

    @try {
        [AxsLiquidGlassLens axs_liquidglass_applyToView:view radius:radius
                                                  fill:fill border:rim
                                              specular:specular perfMode:perfMode];
        // Dock / 文件夹的玻璃本体就是这个 backdrop 层，网格直接挂在它上面，
        // 背景内容会在圆角处真的被弯折 —— 这是"液态"和"调个模糊"的分界线。
        [AxsLiquidGlassMesh axs_liquidglass_applyRefractionToView:view radius:radius
                                                          strength:mesh perfMode:perfMode];
    } @catch (NSException *exception) {
        (void)exception;
        return;
    }

    objc_setAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey, signature,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self axs_liquidglass_registry] addObject:view];
    gAxsBackdropAppliedCount += 1;
    if (gAxsBackdropAppliedCount == 1) {
        AxsLog(@"玻璃膜：首次应用 %@（半径 %.1f，膜 %.2f，边 %.2f，折射 %.2f）",
               NSStringFromClass([view class]), radius, fill, rim, mesh);
    }
}

+ (void)axs_liquidglass_clear:(UIView *)view {
    if (!objc_getAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey)) return;
    [AxsLiquidGlassLens axs_liquidglass_removeFromView:view];
    [AxsLiquidGlassMesh axs_liquidglass_clearRefractionFromView:view];
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
