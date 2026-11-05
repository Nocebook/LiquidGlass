#import "AxsLiquidGlassEffect.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassPrivate.h"
#import "AxsLiquidGlassRim.h"
#import "AxsLiquidGlassSurface.h"

static char kAxsLiquidGlassApplyingKey;
static char kAxsLiquidGlassOriginalKey;
static char kAxsLiquidGlassTrackedKey;
static char kAxsLiquidGlassRetryKey;
static char kAxsLiquidGlassWidgetEdgeKey;

// 小组件进程里唯一的"玻璃感"来源：零新增图层。
// border 只是 CALayer 的绘制属性，不占额外缓冲区、不新增合成层、也不会让快照失败，
// 在 30~50MB 的 widget 内存预算里基本是免费的。
static void axs_liquidglass_applyWidgetEdge(UIView *view, double strength) {
    if (!view.layer) return;
    if (strength <= 0.001) {
        if (objc_getAssociatedObject(view, &kAxsLiquidGlassWidgetEdgeKey)) {
            view.layer.borderWidth = 0.0;
            view.layer.borderColor = nil;
            objc_setAssociatedObject(view, &kAxsLiquidGlassWidgetEdgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    // 系统自己有描边就不覆盖，避免把分隔线之类的原生视觉改掉。
    if (view.layer.borderWidth > 0.01) return;
    view.layer.borderWidth = 0.8;
    view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.20 * strength)].CGColor;
    objc_setAssociatedObject(view, &kAxsLiquidGlassWidgetEdgeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void axs_liquidglass_clearWidgetEdge(UIView *view) {
    if (!view.layer) return;
    if (!objc_getAssociatedObject(view, &kAxsLiquidGlassWidgetEdgeKey)) return;
    view.layer.borderWidth = 0.0;
    view.layer.borderColor = nil;
    objc_setAssociatedObject(view, &kAxsLiquidGlassWidgetEdgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

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
    axs_liquidglass_clearWidgetEdge(view);
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

    BOOL isWidget = [AxsLiquidGlassSurface axs_liquidglass_isWidgetProcess];

    // 视图还没进层级时先等一个 runloop：这时候分类只能靠进程名猜，会把控制中心当成主屏。
    // 小组件进程例外：widget 的渲染窗口只有 8~10 秒，把工作推到下一个 runloop 很可能赶不上
    // 出快照，反而变成"点了没反应"。宁可这一帧不处理，也不延后。
    if (!isWidget && !view.superview && ![objc_getAssociatedObject(view, &kAxsLiquidGlassRetryKey) boolValue]) {
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
    double radius = [config axs_liquidglass_blurRadius];
    double saturation = [config axs_liquidglass_saturation];
    double tintAlpha = [config axs_liquidglass_tintAlpha];
    if (isWidget) {
        // widget 进程只有 30~50MB 可用，模糊半径直接决定 backdrop 的采样缓冲区大小。
        // 主屏 46 在这里太贵，压到 28 并收窄饱和度，视觉仍成立但内存留出余量。
        radius = MIN(radius, 28.0);
        saturation = MIN(saturation, 1.5);
        tintAlpha = MIN(tintAlpha, 0.06);
    }

    UIVisualEffect *effect = [self axs_liquidglass_makeEffectWithRadius:radius
                                                            saturation:saturation
                                                             tintAlpha:tintAlpha];
    if (!effect) return;

    if (!objc_getAssociatedObject(view, &kAxsLiquidGlassOriginalKey)) {
        id original = view.effect ?: (id)[NSNull null];
        objc_setAssociatedObject(view, &kAxsLiquidGlassOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    objc_setAssociatedObject(view, &kAxsLiquidGlassApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.effect = effect;
    objc_setAssociatedObject(view, &kAxsLiquidGlassApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    double rim = [config axs_liquidglass_rimStrength];
    if (isWidget) {
        // 三档语义要严格区分：1 只调参数、2 加零 layer 描边、3 才允许真正的图层高光。
        NSInteger widgetMode = [config axs_liquidglass_widgetMode];
        if (widgetMode >= 3 && rim > 0.001) {
            [AxsLiquidGlassRim axs_liquidglass_installOnView:view strength:rim];
            axs_liquidglass_clearWidgetEdge(view);
        } else if (widgetMode == 2 && rim > 0.001) {
            [AxsLiquidGlassRim axs_liquidglass_removeFromView:view];
            axs_liquidglass_applyWidgetEdge(view, rim);
        } else {
            [AxsLiquidGlassRim axs_liquidglass_removeFromView:view];
            axs_liquidglass_clearWidgetEdge(view);
        }
    } else if ([AxsLiquidGlassSurface axs_liquidglass_allowsDecorativeLayersForKind:kind] && rim > 0.001) {
        [AxsLiquidGlassRim axs_liquidglass_installOnView:view strength:rim];
    } else {
        [AxsLiquidGlassRim axs_liquidglass_removeFromView:view];
    }

    objc_setAssociatedObject(view, &kAxsLiquidGlassTrackedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self axs_liquidglass_registry] addObject:view];

    // 模糊效果设完时视图可能还没排过版，补一次几何同步。
    // 小组件必须同步补齐：渲染窗口只有 8~10 秒，延迟到下一个 runloop 很可能赶不上出快照。
    if (isWidget) {
        [AxsLiquidGlassRim axs_liquidglass_layoutInView:view];
    } else {
        __weak UIView *weakView = view;
        dispatch_async(dispatch_get_main_queue(), ^{
            [AxsLiquidGlassRim axs_liquidglass_layoutInView:weakView];
        });
    }
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
