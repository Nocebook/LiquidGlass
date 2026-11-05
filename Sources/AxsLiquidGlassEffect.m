#import "AxsLiquidGlassEffect.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassPrivate.h"
#import "AxsLiquidGlassRim.h"
#import "AxsLiquidGlassSurface.h"

static char kAxsLiquidGlassApplyingKey;
static char kAxsLiquidGlassOriginalKey;
static char kAxsLiquidGlassTrackedKey;
static char kAxsLiquidGlassRetryKey;

@implementation AxsLiquidGlassEffect

+ (NSHashTable<UIView *> *)axs_liquidglass_registry {
    static NSHashTable<UIView *> *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSHashTable weakObjectsHashTable];
    });
    return registry;
}

+ (BOOL)axs_liquidglass_isApplyingToView:(UIView *)view {
    return [objc_getAssociatedObject(view, &kAxsLiquidGlassApplyingKey) boolValue];
}

+ (BOOL)axs_liquidglass_isTrackedView:(UIView *)view {
    return [objc_getAssociatedObject(view, &kAxsLiquidGlassTrackedKey) boolValue];
}

+ (void)axs_liquidglass_untrackView:(UIView *)view {
    objc_setAssociatedObject(view, &kAxsLiquidGlassTrackedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (UIVisualEffect *)axs_liquidglass_makeEffectWithRadius:(double)radius
                                              saturation:(double)saturation
                                               tintAlpha:(double)tintAlpha {
    id blurClass = AxsLiquidGlassBlurEffectClass();
    if (blurClass) {
        id effect = [[blurClass alloc] init];
        BOOL accepted = AxsLiquidGlassSetNumber(effect, @"setBlurRadius:", @"blurRadius", radius);
        AxsLiquidGlassSetNumber(effect, @"setSaturationDeltaFactor:", @"saturationDeltaFactor", saturation);
        AxsLiquidGlassSetNumber(effect, @"setColorTintAlpha:", @"colorTintAlpha", tintAlpha);
        AxsLiquidGlassSetObject(effect, @"setTintColor:", @"tintColor", [UIColor whiteColor]);
        if (accepted) return effect;
    }
    // 私有类不在时退回系统材质，宁可没有玻璃质感也不让界面变透明。
    if (@available(iOS 13.0, *)) {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
}

+ (void)axs_liquidglass_restoreView:(UIVisualEffectView *)view {
    if (!view) return;
    id original = objc_getAssociatedObject(view, &kAxsLiquidGlassOriginalKey);
    if (original) {
        objc_setAssociatedObject(view, &kAxsLiquidGlassApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.effect = (original == [NSNull null]) ? nil : (UIVisualEffect *)original;
        objc_setAssociatedObject(view, &kAxsLiquidGlassApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kAxsLiquidGlassOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [AxsLiquidGlassRim axs_liquidglass_removeFromView:view];
    [self axs_liquidglass_untrackView:view];
}

+ (void)axs_liquidglass_applyToEffectView:(UIVisualEffectView *)view {
    if (!view) return;
    if (![NSThread isMainThread]) {
        __weak UIVisualEffectView *weakView = view;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self axs_liquidglass_applyToEffectView:weakView];
        });
        return;
    }
    if ([self axs_liquidglass_isApplyingToView:view]) return;

    // 视图还没进层级时先等一个 runloop：这时候分类只能靠进程名猜，会把控制中心当成主屏。
    if (!view.superview && ![objc_getAssociatedObject(view, &kAxsLiquidGlassRetryKey) boolValue]) {
        objc_setAssociatedObject(view, &kAxsLiquidGlassRetryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIVisualEffectView *weakView = view;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self axs_liquidglass_applyToEffectView:weakView];
        });
        return;
    }

    // 只在模糊效果上动手；vibrancy 之类的视图换成模糊会直接坏掉。
    UIVisualEffect *current = view.effect;
    if (current && ![current isKindOfClass:[UIBlurEffect class]]) return;

    AxsLiquidGlassSurfaceKind kind = [AxsLiquidGlassSurface axs_liquidglass_kindForView:view];
    if (![AxsLiquidGlassSurface axs_liquidglass_shouldHandleView:view kind:kind]) {
        [self axs_liquidglass_restoreView:view];
        return;
    }

    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    UIVisualEffect *effect = [self axs_liquidglass_makeEffectWithRadius:[config axs_liquidglass_blurRadius]
                                                            saturation:[config axs_liquidglass_saturation]
                                                             tintAlpha:[config axs_liquidglass_tintAlpha]];
    if (!effect) return;

    if (!objc_getAssociatedObject(view, &kAxsLiquidGlassOriginalKey)) {
        id original = view.effect ?: (id)[NSNull null];
        objc_setAssociatedObject(view, &kAxsLiquidGlassOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    objc_setAssociatedObject(view, &kAxsLiquidGlassApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.effect = effect;
    objc_setAssociatedObject(view, &kAxsLiquidGlassApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    double rim = [config axs_liquidglass_rimStrength];
    if ([AxsLiquidGlassSurface axs_liquidglass_allowsDecorativeLayersForKind:kind] && rim > 0.001) {
        [AxsLiquidGlassRim axs_liquidglass_installOnView:view strength:rim];
    } else {
        [AxsLiquidGlassRim axs_liquidglass_removeFromView:view];
    }

    objc_setAssociatedObject(view, &kAxsLiquidGlassTrackedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self axs_liquidglass_registry] addObject:view];

    // 模糊效果设完时视图可能还没排过版，补一次几何同步。
    __weak UIView *weakView = view;
    dispatch_async(dispatch_get_main_queue(), ^{
        [AxsLiquidGlassRim axs_liquidglass_layoutInView:weakView];
    });
}

+ (void)axs_liquidglass_layoutTrackedView:(UIView *)view {
    if (![self axs_liquidglass_isTrackedView:view]) return;
    [AxsLiquidGlassRim axs_liquidglass_layoutInView:view];
}

+ (void)axs_liquidglass_handleEffectChange:(UIVisualEffectView *)view {
    if ([self axs_liquidglass_isApplyingToView:view]) return;
    [self axs_liquidglass_applyToEffectView:view];
}

+ (void)axs_liquidglass_handleHierarchyChange:(UIVisualEffectView *)view {
    if ([self axs_liquidglass_isTrackedView:view]) return;
    [self axs_liquidglass_applyToEffectView:view];
}

+ (void)axs_liquidglass_refreshTrackedViews {
    NSArray<UIView *> *views = [[self axs_liquidglass_registry] allObjects];
    for (UIView *view in views) {
        if (![view isKindOfClass:[UIVisualEffectView class]]) continue;
        [self axs_liquidglass_applyToEffectView:(UIVisualEffectView *)view];
    }
}

+ (void)axs_liquidglass_stripDecorativeLayers {
    NSArray<UIView *> *views = [[self axs_liquidglass_registry] allObjects];
    for (UIView *view in views) {
        [AxsLiquidGlassRim axs_liquidglass_removeFromView:view];
    }
}

@end
