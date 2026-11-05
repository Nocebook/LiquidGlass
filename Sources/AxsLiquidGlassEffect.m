#import "AxsLiquidGlassEffect.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassPrivate.h"
#import "AxsLiquidGlassLens.h"
#import "AxsLiquidGlassMesh.h"
#import "AxsLiquidGlassSurface.h"

static char kAxsLiquidGlassApplyingKey;
static char kAxsLiquidGlassOriginalKey;
static char kAxsLiquidGlassTrackedKey;
static char kAxsLiquidGlassRetryKey;
static char kAxsLiquidGlassWidgetEdgeKey;

@interface AxsLiquidGlassEffect ()
/// 从自身或最近的祖先上取真实圆角：系统大量卡片是"父视图裁圆角、子视图 0"。
/// 只看自己会判成直角，玻璃膜和折射网格都会画歪。
+ (CGFloat)axs_liquidglass_radiusForView:(UIView *)view;
@end

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

/// 这块表面占窗口面积多少：用来把"药丸级玻璃"和"整屏模糊底"分开。
static double axs_liquidglass_areaRatio(UIView *view) {
    UIView *reference = view.window ?: view;
    CGRect referenceBounds = reference.bounds;
    double referenceArea = (double)CGRectGetWidth(referenceBounds) * (double)CGRectGetHeight(referenceBounds);
    if (referenceArea <= 0.0) return 0.0;
    CGRect bounds = view.bounds;
    return ((double)CGRectGetWidth(bounds) * (double)CGRectGetHeight(bounds)) / referenceArea;
}

@implementation AxsLiquidGlassEffect

+ (CGFloat)axs_liquidglass_radiusForView:(UIView *)view {
    if (!view) return 0.0;
    if (view.layer.cornerRadius >= 1.0) return view.layer.cornerRadius;
    // 不少系统卡片把圆角放在祖先上，且不一定设 masksToBounds（用 mask 图层裁）。
    // 早期版本要求 masksToBounds 才认，结果控制中心里的 UIVisualEffectView 全被判成直角，
    // 玻璃膜按 0 圆角铺满整块 → 方角上一圈白雾。这里放宽到只看 cornerRadius。
    UIView *current = view.superview;
    for (NSInteger depth = 0; current && depth < 8; depth++) {
        if (current.layer.cornerRadius >= 1.0) return current.layer.cornerRadius;
        current = current.superview;
    }
    return 0.0;
}

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
    [AxsLiquidGlassLens axs_liquidglass_removeFromView:view];
    [AxsLiquidGlassMesh axs_liquidglass_clearRefractionFromView:view];
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
    double fill = [config axs_liquidglass_fillAlpha];
    double specular = [config axs_liquidglass_specularStrength];
    double mesh = [config axs_liquidglass_meshStrength];
    NSInteger perfMode = [config axs_liquidglass_perfMode];
    CGFloat cornerRadius = [self axs_liquidglass_radiusForView:view];

    if (isWidget) {
        // 三档语义要严格区分：1 只调参数、2 加零 layer 描边、3 才允许真正的图层。
        // 小组件进程只有 30~50MB 预算，档位 3 也强制走省电参数，不给它上折射网格。
        NSInteger widgetMode = [config axs_liquidglass_widgetMode];
        if (widgetMode >= 3 && rim > 0.001 && cornerRadius >= 4.0) {
            [AxsLiquidGlassLens axs_liquidglass_applyToView:view radius:cornerRadius
                                                       fill:fill * 0.55 border:rim
                                                   specular:specular * 0.5 perfMode:0];
            axs_liquidglass_clearWidgetEdge(view);
        } else if (widgetMode == 2 && rim > 0.001) {
            [AxsLiquidGlassLens axs_liquidglass_removeFromView:view];
            axs_liquidglass_applyWidgetEdge(view, rim);
        } else {
            [AxsLiquidGlassLens axs_liquidglass_removeFromView:view];
            axs_liquidglass_clearWidgetEdge(view);
        }
    } else if ([AxsLiquidGlassSurface axs_liquidglass_allowsDecorativeLayersForKind:kind]) {
        // 主屏 / 控制中心 / 通知：玻璃膜 + 边缘折射，这一组才是"液态"观感的来源。
        // 两条硬约束：
        //   · 圆角 < 4 的表面不铺膜 —— 方角上铺一层白雾就是"看着很脏"的元凶；
        //   · 超过窗口 62% 面积的表面是整屏模糊底，铺膜会把整屏洗白，只留模糊。
        double ratio = axs_liquidglass_areaRatio(view);
        BOOL tooLarge = ratio > 0.62;
        if (cornerRadius >= 4.0 && !tooLarge) {
            [AxsLiquidGlassLens axs_liquidglass_applyToView:view radius:cornerRadius
                                                       fill:fill border:rim
                                                   specular:specular perfMode:perfMode];
            [AxsLiquidGlassMesh axs_liquidglass_applyRefractionToView:view radius:cornerRadius
                                                              strength:mesh perfMode:perfMode];
        } else {
            [AxsLiquidGlassLens axs_liquidglass_removeFromView:view];
            [AxsLiquidGlassMesh axs_liquidglass_clearRefractionFromView:view];
            if (cornerRadius < 4.0) {
                static BOOL loggedRightAngle = NO;
                if (!loggedRightAngle) {
                    loggedRightAngle = YES;
                    AxsLog(@"玻璃膜：%@ 判定为直角（圆角 %.1f），只保留模糊", NSStringFromClass([view class]), cornerRadius);
                }
            }
        }
    } else {
        [AxsLiquidGlassLens axs_liquidglass_removeFromView:view];
        [AxsLiquidGlassMesh axs_liquidglass_clearRefractionFromView:view];
    }

    objc_setAssociatedObject(view, &kAxsLiquidGlassTrackedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self axs_liquidglass_registry] addObject:view];

    // 模糊效果设完时视图可能还没排过版，补一次几何同步。
    // 小组件必须同步补齐：渲染窗口只有 8~10 秒，延迟到下一个 runloop 很可能赶不上出快照。
    if (isWidget) {
        [AxsLiquidGlassLens axs_liquidglass_layoutView:view radius:[self axs_liquidglass_radiusForView:view]];
    } else {
        __weak UIView *weakView = view;
        dispatch_async(dispatch_get_main_queue(), ^{
            [AxsLiquidGlassLens axs_liquidglass_layoutView:weakView radius:[self axs_liquidglass_radiusForView:weakView]];
        });
    }
}

+ (void)axs_liquidglass_layoutTrackedView:(UIView *)view {
    if (![self axs_liquidglass_isTrackedView:view]) return;
    [AxsLiquidGlassLens axs_liquidglass_layoutView:view radius:[self axs_liquidglass_radiusForView:view]];
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
        [AxsLiquidGlassLens axs_liquidglass_removeFromView:view];
        [AxsLiquidGlassMesh axs_liquidglass_clearRefractionFromView:view];
    }
}

@end
