#import "AxsLiquidGlassRim.h"
#import "AxsLiquidGlassPrivate.h"

static char kAxsLiquidGlassSheenKey;
static char kAxsLiquidGlassEdgeKey;

@implementation AxsLiquidGlassRim

+ (void)axs_liquidglass_installOnView:(UIView *)view strength:(double)strength {
    if (!view) return;
    double clamped = AxsLiquidGlassClamp(strength, 0.0, 1.0);
    if (clamped <= 0.001) {
        [self axs_liquidglass_removeFromView:view];
        return;
    }

    CAGradientLayer *sheen = objc_getAssociatedObject(view, &kAxsLiquidGlassSheenKey);
    if (!sheen) {
        sheen = [CAGradientLayer layer];
        sheen.name = @"axs.liquidglass.sheen";
        sheen.startPoint = CGPointMake(0.0, 0.0);
        sheen.endPoint = CGPointMake(0.72, 1.0);
        sheen.zPosition = 900.0;
        [view.layer addSublayer:sheen];
        objc_setAssociatedObject(view, &kAxsLiquidGlassSheenKey, sheen, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // 光从左上进来，到中段就散干净；alpha 跟着强度走，不做整块蒙白。
    CGFloat highlight = (CGFloat)(0.16 * clamped);
    sheen.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:highlight].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:highlight * 0.35].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    sheen.locations = @[@0.0, @0.45, @1.0];

    CAShapeLayer *edge = objc_getAssociatedObject(view, &kAxsLiquidGlassEdgeKey);
    if (!edge) {
        edge = [CAShapeLayer layer];
        edge.name = @"axs.liquidglass.edge";
        edge.fillColor = [UIColor clearColor].CGColor;
        edge.zPosition = 901.0;
        [view.layer addSublayer:edge];
        objc_setAssociatedObject(view, &kAxsLiquidGlassEdgeKey, edge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    edge.strokeColor = [UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.22 * clamped)].CGColor;
    edge.lineWidth = 1.0;

    [self axs_liquidglass_layoutInView:view];
}

+ (void)axs_liquidglass_removeFromView:(UIView *)view {
    if (!view) return;
    CAGradientLayer *sheen = objc_getAssociatedObject(view, &kAxsLiquidGlassSheenKey);
    if (sheen) {
        [sheen removeFromSuperlayer];
        objc_setAssociatedObject(view, &kAxsLiquidGlassSheenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CAShapeLayer *edge = objc_getAssociatedObject(view, &kAxsLiquidGlassEdgeKey);
    if (edge) {
        [edge removeFromSuperlayer];
        objc_setAssociatedObject(view, &kAxsLiquidGlassEdgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

+ (BOOL)axs_liquidglass_hasRim:(UIView *)view {
    return objc_getAssociatedObject(view, &kAxsLiquidGlassSheenKey) != nil;
}

+ (void)axs_liquidglass_layoutInView:(UIView *)view {
    if (!view) return;
    CAGradientLayer *sheen = objc_getAssociatedObject(view, &kAxsLiquidGlassSheenKey);
    CAShapeLayer *edge = objc_getAssociatedObject(view, &kAxsLiquidGlassEdgeKey);
    if (!sheen && !edge) return;

    CGRect bounds = view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width < 1.0 || height < 1.0) return;

    // 图层坐标从 0 开始，跟 bounds.origin 解耦，避免二次偏移。
    CGRect localRect = CGRectMake(0.0, 0.0, width, height);
    sheen.frame = localRect;

    CGFloat radius = view.layer.cornerRadius;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(localRect, 0.5, 0.5)
                                                    cornerRadius:MAX(0.0, radius - 0.5)];
    edge.frame = localRect;
    edge.path = path.CGPath;
}

@end
