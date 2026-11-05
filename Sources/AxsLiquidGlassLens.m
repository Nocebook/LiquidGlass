#import "AxsLiquidGlassLens.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char kAxsLensContainerKey;
static char kAxsLensFillKey;
static char kAxsLensSpecularKey;
static char kAxsLensBorderKey;
static char kAxsLensBorderMaskKey;
static char kAxsLensShadowKey;
static char kAxsLensSignatureKey;
static char kAxsLensGeometryKey;

static NSInteger gAxsLensAppliedCount = 0;

/// 把玻璃膜插在 backdrop 层的正上方、真实内容层的下方。
/// 直接 addSublayer 会盖到子视图上面（文字发白）；插到 index 0 又会被模糊盖住。
static void AxsInsertLensContainer(UIView *view, CALayer *container) {
    NSArray<CALayer *> *sublayers = view.layer.sublayers;
    NSUInteger index = 0;
    for (NSUInteger i = 0; i < sublayers.count; i++) {
        NSString *name = NSStringFromClass([sublayers[i] class]);
        if ([name containsString:@"Backdrop"]) {
            index = i + 1;
            break;
        }
    }
    @try {
        [view.layer insertSublayer:container atIndex:(unsigned int)index];
    } @catch (NSException *exception) {
        (void)exception;
        [view.layer addSublayer:container];
    }
}


@implementation AxsLiquidGlassLens

+ (BOOL)axs_liquidglass_hasLens:(UIView *)view {
    return objc_getAssociatedObject(view, &kAxsLensContainerKey) != nil;
}

+ (void)axs_liquidglass_applyToView:(UIView *)view
                             radius:(CGFloat)radius
                               fill:(double)fill
                             border:(double)border
                           specular:(double)specular
                           perfMode:(NSInteger)perfMode {
    if (!view || !view.layer) return;
    if (![NSThread isMainThread]) return;

    // 省电档：不要镜面高光，膜也压淡一半，只留描边保证"有玻璃边"。
    if (perfMode <= 0) {
        specular = 0.0;
        fill *= 0.55;
    }

    if (fill <= 0.001 && border <= 0.001 && specular <= 0.001) {
        [self axs_liquidglass_removeFromView:view];
        return;
    }

    CGFloat clampedRadius = MAX(0.0, radius);
    NSString *signature = [NSString stringWithFormat:@"%.1f|%.3f|%.3f|%.3f|%ld",
                           clampedRadius, fill, border, specular, (long)perfMode];
    NSString *previous = objc_getAssociatedObject(view, &kAxsLensSignatureKey);
    CALayer *container = objc_getAssociatedObject(view, &kAxsLensContainerKey);

    // 参数没变且图层还在：只补一次几何，不做任何重建。这是控制中心反复开关时的主路径。
    if (container && [previous isEqualToString:signature]) {
        [self axs_liquidglass_layoutView:view radius:clampedRadius];
        return;
    }

    if (!container) {
        container = [CALayer layer];
        container.name = @"heli.liquid.lens";
        container.zPosition = 0.0;
        container.masksToBounds = YES;
        objc_setAssociatedObject(view, &kAxsLensContainerKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        AxsInsertLensContainer(view, container);
    }

    if (@available(iOS 13.0, *)) {
        container.cornerCurve = kCACornerCurveContinuous;
    }

    // 1. 玻璃本体：上亮下暗的极淡乳白
    CAGradientLayer *fillLayer = objc_getAssociatedObject(view, &kAxsLensFillKey);
    if (!fillLayer) {
        fillLayer = [CAGradientLayer layer];
        fillLayer.name = @"heli.liquid.fill";
        fillLayer.startPoint = CGPointMake(0.0, 0.0);
        fillLayer.endPoint = CGPointMake(0.0, 1.0);
        [container addSublayer:fillLayer];
        objc_setAssociatedObject(view, &kAxsLensFillKey, fillLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    fillLayer.hidden = (fill <= 0.001);
    fillLayer.colors = @[
        (id)[UIColor colorWithRed:0.98 green:0.99 blue:1.0 alpha:(CGFloat)fill].CGColor,
        (id)[UIColor colorWithRed:0.90 green:0.94 blue:1.0 alpha:(CGFloat)(fill * 0.45)].CGColor
    ];
    fillLayer.locations = @[@0.0, @1.0];

    // 2. 镜面高光：左上角一团柔光，对应真实玻璃的主光源
    CAGradientLayer *specularLayer = objc_getAssociatedObject(view, &kAxsLensSpecularKey);
    if (!specularLayer) {
        specularLayer = [CAGradientLayer layer];
        specularLayer.name = @"heli.liquid.specular";
        specularLayer.type = kCAGradientLayerRadial;
        specularLayer.startPoint = CGPointMake(0.16, 0.02);
        specularLayer.endPoint = CGPointMake(0.82, 0.95);
        [container addSublayer:specularLayer];
        objc_setAssociatedObject(view, &kAxsLensSpecularKey, specularLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    specularLayer.hidden = (specular <= 0.001);
    specularLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.34 * specular)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.10 * specular)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    specularLayer.locations = @[@0.0, @0.42, @1.0];

    // 3. 底边内阴影
    CAGradientLayer *shadowLayer = objc_getAssociatedObject(view, &kAxsLensShadowKey);
    if (!shadowLayer) {
        shadowLayer = [CAGradientLayer layer];
        shadowLayer.name = @"heli.liquid.shadow";
        shadowLayer.startPoint = CGPointMake(0.0, 0.0);
        shadowLayer.endPoint = CGPointMake(0.0, 1.0);
        [container addSublayer:shadowLayer];
        objc_setAssociatedObject(view, &kAxsLensShadowKey, shadowLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    shadowLayer.hidden = (border <= 0.001);
    shadowLayer.colors = @[
        (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:(CGFloat)(0.10 * border)].CGColor
    ];
    shadowLayer.locations = @[@0.0, @0.62, @1.0];

    // 4. 定向描边：左上亮 → 中段暗 → 右下回亮，这是"玻璃有厚度"的关键。
    //    用一个渐变层 + 圆角路径描边做 mask，比 borderWidth 的纯白边自然得多。
    CAGradientLayer *borderLayer = objc_getAssociatedObject(view, &kAxsLensBorderKey);
    if (!borderLayer) {
        borderLayer = [CAGradientLayer layer];
        borderLayer.name = @"heli.liquid.border";
        borderLayer.startPoint = CGPointMake(0.0, 0.0);
        borderLayer.endPoint = CGPointMake(1.0, 1.0);
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.name = @"heli.liquid.border.mask";
        mask.fillColor = [UIColor clearColor].CGColor;
        mask.strokeColor = [UIColor whiteColor].CGColor;
        borderLayer.mask = mask;
        objc_setAssociatedObject(view, &kAxsLensBorderMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [container addSublayer:borderLayer];
        objc_setAssociatedObject(view, &kAxsLensBorderKey, borderLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    borderLayer.hidden = (border <= 0.001);
    borderLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.85 * border)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.10 * border)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.52 * border)].CGColor
    ];
    borderLayer.locations = @[@0.0, @0.48, @1.0];

    CAShapeLayer *mask = objc_getAssociatedObject(view, &kAxsLensBorderMaskKey);
    mask.lineWidth = (CGFloat)(0.9 + 0.9 * border);

    objc_setAssociatedObject(view, &kAxsLensSignatureKey, signature, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self axs_liquidglass_layoutView:view radius:clampedRadius];

    gAxsLensAppliedCount += 1;
    if (gAxsLensAppliedCount == 1) {
        AxsLog(@"玻璃膜：首次生效 %@（圆角 %.0f，膜 %.2f，边 %.2f，高光 %.2f，档位 %ld）",
               NSStringFromClass([view class]), clampedRadius, fill, border, specular, (long)perfMode);
    }
}

+ (void)axs_liquidglass_layoutView:(UIView *)view radius:(CGFloat)radius {
    if (!view) return;
    CALayer *container = objc_getAssociatedObject(view, &kAxsLensContainerKey);
    if (!container) return;

    CGRect bounds = view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width < 1.0 || height < 1.0) return;

    // 尺寸和圆角都没变就直接返回：layoutSubviews 在滚动/展开动画里每帧都调，
    // 重建描边路径是这个模块里最没必要的一笔开销。
    NSString *geometry = [NSString stringWithFormat:@"%.1fx%.1f|%.1f", width, height, radius];
    if ([objc_getAssociatedObject(view, &kAxsLensGeometryKey) isEqual:geometry]) return;
    objc_setAssociatedObject(view, &kAxsLensGeometryKey, geometry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 用图层自己的坐标（从 0 开始），跟 bounds.origin 解耦，滚动时不会二次偏移。
    container.frame = CGRectMake(0.0, 0.0, width, height);
    container.cornerRadius = MAX(0.0, radius);

    CGRect localRect = CGRectMake(0.0, 0.0, width, height);
    for (NSString *key in @[@"fill", @"specular", @"shadow"]) {
        CALayer *layer = nil;
        if ([key isEqualToString:@"fill"]) layer = objc_getAssociatedObject(view, &kAxsLensFillKey);
        if ([key isEqualToString:@"specular"]) layer = objc_getAssociatedObject(view, &kAxsLensSpecularKey);
        if ([key isEqualToString:@"shadow"]) layer = objc_getAssociatedObject(view, &kAxsLensShadowKey);
        layer.frame = localRect;
    }

    CAGradientLayer *borderLayer = objc_getAssociatedObject(view, &kAxsLensBorderKey);
    CAShapeLayer *mask = objc_getAssociatedObject(view, &kAxsLensBorderMaskKey);
    if (borderLayer && mask) {
        borderLayer.frame = localRect;
        CGFloat lineWidth = mask.lineWidth > 0.1 ? mask.lineWidth : 1.2;
        // 描边路径内缩半个线宽：正好整个笔画都落在容器里面，
        // 不会被容器的 masksToBounds 削掉外侧一半。
        CGRect strokeRect = CGRectInset(localRect, lineWidth * 0.5, lineWidth * 0.5);
        CGFloat strokeRadius = MAX(0.0, MAX(0.0, radius) - lineWidth * 0.5);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:strokeRect
                                                       cornerRadius:strokeRadius];
        mask.frame = localRect;
        mask.path = path.CGPath;
    }
}

+ (void)axs_liquidglass_removeFromView:(UIView *)view {
    if (!view) return;
    CALayer *container = objc_getAssociatedObject(view, &kAxsLensContainerKey);
    if (!container) return;

    [container removeFromSuperlayer];
    objc_setAssociatedObject(view, &kAxsLensContainerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kAxsLensFillKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kAxsLensSpecularKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kAxsLensBorderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kAxsLensBorderMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kAxsLensShadowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kAxsLensSignatureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kAxsLensGeometryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
