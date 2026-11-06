#import "AxsLiquidGlassLens.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <string.h>

static char kAxsLensContainerKey;
static char kAxsLensFillKey;
static char kAxsLensSpecularKey;
static char kAxsLensBorderKey;
static char kAxsLensBorderMaskKey;
static char kAxsLensSignatureKey;
static char kAxsLensGeometryKey;

static NSInteger gAxsLensAppliedCount = 0;

#pragma mark - 几何

/// 参数签名。用结构体而不是格式化字符串：这个比较在滚动时是逐帧的，
/// 每次拼一个 NSString 会持续制造临时对象，十几块玻璃叠起来就是每帧十几次分配。
typedef struct {
    float radius;
    float fill;
    float border;
    float specular;
    int perfMode;
    int dark;
} AxsLensSignature;

typedef struct {
    float width;
    float height;
    float radius;
} AxsLensGeometry;

static BOOL AxsLensIsDark(UIView *view) {
    if (@available(iOS 12.0, *)) {
        return view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

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
    BOOL dark = AxsLensIsDark(view);

    AxsLensSignature signature;
    signature.radius = (float)clampedRadius;
    signature.fill = (float)fill;
    signature.border = (float)border;
    signature.specular = (float)specular;
    signature.perfMode = (int)perfMode;
    signature.dark = (int)dark;
    NSData *previous = objc_getAssociatedObject(view, &kAxsLensSignatureKey);
    CALayer *container = objc_getAssociatedObject(view, &kAxsLensContainerKey);

    // 参数没变且图层还在：只补一次几何，不做任何重建。这是控制中心反复开关时的主路径。
    // 用 memcmp 比对，不分配对象 —— 滚动时这个判断是逐帧的。
    if (container && [previous isKindOfClass:[NSData class]] &&
        previous.length == sizeof(signature) &&
        memcmp(previous.bytes, &signature, sizeof(signature)) == 0) {
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

    // 1+3 合并成一层：玻璃本体（上亮下暗的极淡乳白）+ 底边内阴影。
    //    早期是两层渐变上下叠着画，每块表面多一次全幅 alpha 混合；
    //    合成到同一条竖直渐变里，观感几乎一致，但少了一个图层、少一遍混合。
    //    暗色界面下不能再用纯白 —— 白膜落在深色底上会发灰，改成低透明度本色 + 更深的收口。
    CAGradientLayer *fillLayer = objc_getAssociatedObject(view, &kAxsLensFillKey);
    if (!fillLayer) {
        fillLayer = [CAGradientLayer layer];
        fillLayer.name = @"heli.liquid.fill";
        fillLayer.startPoint = CGPointMake(0.0, 0.0);
        fillLayer.endPoint = CGPointMake(0.0, 1.0);
        [container addSublayer:fillLayer];
        objc_setAssociatedObject(view, &kAxsLensFillKey, fillLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    fillLayer.hidden = (fill <= 0.001 && border <= 0.001);
    CGFloat shadowAlpha = (CGFloat)((dark ? 0.22 : 0.10) * border);
    if (dark) {
        fillLayer.colors = @[
            (id)[UIColor colorWithWhite:0.62 alpha:(CGFloat)(fill * 0.55)].CGColor,
            (id)[UIColor colorWithWhite:0.42 alpha:(CGFloat)(fill * 0.30)].CGColor,
            (id)[UIColor colorWithWhite:0.20 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:shadowAlpha].CGColor
        ];
    } else {
        fillLayer.colors = @[
            (id)[UIColor colorWithRed:0.98 green:0.99 blue:1.0 alpha:(CGFloat)fill].CGColor,
            (id)[UIColor colorWithRed:0.90 green:0.94 blue:1.0 alpha:(CGFloat)(fill * 0.62)].CGColor,
            (id)[UIColor colorWithRed:0.86 green:0.90 blue:1.0 alpha:0.0].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:shadowAlpha].CGColor
        ];
    }
    fillLayer.locations = @[@0.0, @0.42, @0.80, @1.0];

    // 2. 镜面高光：左上角一团柔光，对应真实玻璃的主光源。
    //    省电档（specular 被压成 0）时连图层都不建 —— 一块整幅的径向渐变
    //    在任何界面上都是实打实的一次合成，省电档下没有理由留着它。
    CAGradientLayer *specularLayer = objc_getAssociatedObject(view, &kAxsLensSpecularKey);
    if (specular > 0.001) {
        if (!specularLayer) {
            specularLayer = [CAGradientLayer layer];
            specularLayer.name = @"heli.liquid.specular";
            specularLayer.type = kCAGradientLayerRadial;
            specularLayer.startPoint = CGPointMake(0.16, 0.02);
            specularLayer.endPoint = CGPointMake(0.82, 0.95);
            [container addSublayer:specularLayer];
            objc_setAssociatedObject(view, &kAxsLensSpecularKey, specularLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        specularLayer.hidden = NO;
        CGFloat specularGain = dark ? 0.26 : 0.32;
        specularLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(specularGain * specular)].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.09 * specular)].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
        ];
        specularLayer.locations = @[@0.0, @0.42, @1.0];
    } else if (specularLayer) {
        specularLayer.hidden = YES;
    }

    // 4. 定向描边（重写）。
    //    旧实现是线性对角渐变 + 白边，观感上"整圈一样亮"，不像玻璃。
    //    真玻璃的反射是沿圆角一圈扫过的：左上最亮 → 右上快速衰减 → 底边几乎全暗 → 左下回亮。
    //    用锥形渐变（conic）以中心为原点绕一圈，再拿圆角路径描边当 mask，光就"绕着边走"。
    CAGradientLayer *borderLayer = objc_getAssociatedObject(view, &kAxsLensBorderKey);
    if (!borderLayer) {
        borderLayer = [CAGradientLayer layer];
        borderLayer.name = @"heli.liquid.border";
        borderLayer.startPoint = CGPointMake(0.5, 0.5);
        borderLayer.endPoint = CGPointMake(0.5, 0.0);   // 0 度从正上方开始，顺时针
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
    if (@available(iOS 12.0, *)) {
        borderLayer.type = kCAGradientLayerConic;
    }
    // 角度对应：0 正上 / 0.25 右 / 0.5 下 / 0.75 左。
    // 峰值放在 0.86（左上），次峰 0.12（右上），底边 0.5 附近压到几乎全暗。
    CGFloat keyGain = dark ? 0.95 : 0.88;
    borderLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.30 * keyGain * border)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.62 * keyGain * border)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.14 * keyGain * border)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.04 * keyGain * border)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.26 * keyGain * border)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.95 * keyGain * border)].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.46 * keyGain * border)].CGColor
    ];
    borderLayer.locations = @[@0.0, @0.12, @0.32, @0.52, @0.72, @0.86, @0.96];

    CAShapeLayer *mask = objc_getAssociatedObject(view, &kAxsLensBorderMaskKey);
    mask.lineWidth = (CGFloat)(0.9 + 0.9 * border);

    objc_setAssociatedObject(view, &kAxsLensSignatureKey,
                             [NSData dataWithBytes:&signature length:sizeof(signature)],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self axs_liquidglass_layoutView:view radius:clampedRadius];

    gAxsLensAppliedCount += 1;
    if (gAxsLensAppliedCount == 1) {
        AxsLog(@"玻璃膜：首次生效 %@（圆角 %.0f，膜 %.2f，边 %.2f，高光 %.2f，档位 %ld，%s）",
               NSStringFromClass([view class]), clampedRadius, fill, border, specular,
               (long)perfMode, dark ? "暗色" : "亮色");
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
    AxsLensGeometry geometry;
    geometry.width = (float)width;
    geometry.height = (float)height;
    geometry.radius = (float)radius;
    NSData *previousGeometry = objc_getAssociatedObject(view, &kAxsLensGeometryKey);
    if ([previousGeometry isKindOfClass:[NSData class]] &&
        previousGeometry.length == sizeof(geometry) &&
        memcmp(previousGeometry.bytes, &geometry, sizeof(geometry)) == 0) return;
    objc_setAssociatedObject(view, &kAxsLensGeometryKey,
                             [NSData dataWithBytes:&geometry length:sizeof(geometry)],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 用图层自己的坐标（从 0 开始），跟 bounds.origin 解耦，滚动时不会二次偏移。
    container.frame = CGRectMake(0.0, 0.0, width, height);
    container.cornerRadius = MAX(0.0, radius);

    CGRect localRect = CGRectMake(0.0, 0.0, width, height);
    CALayer *fillLayer = objc_getAssociatedObject(view, &kAxsLensFillKey);
    CALayer *specularLayer = objc_getAssociatedObject(view, &kAxsLensSpecularKey);
    fillLayer.frame = localRect;
    specularLayer.frame = localRect;

    // 锥形渐变的几何跟线性不同：startPoint 是圆心，endPoint 只决定起始角。
    // 半径变化时圆心始终在正中间，这里跟 bounds 一起保持在 0.5/0.5 即可。
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
    objc_setAssociatedObject(view, &kAxsLensSignatureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kAxsLensGeometryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
