#import "AxsLiquidGlassBadge.h"

#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

#import <substrate.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

// 角标视图 -> 我们插进去的玻璃层
static char kAxsBadgeGlassKey;
// 角标视图 -> 原始外观快照（底板色 + 每个子视图原来的 alpha），卸载时逐项还原
static char kAxsBadgeSnapshotKey;
// layoutSubviews 里的重入保护
static char kAxsBadgeReassertKey;

static BOOL gAxsBadgeInstalled = NO;
static NSInteger gAxsBadgeAttachedCount = 0;

#pragma mark - 玻璃层

/// 一枚角标大小的玻璃。只有四个静态图层，没有定时器、没有逐帧回调：
///   blur    极薄材质，让底下壁纸透上来（可关，关掉纯靠乳白渐变）
///   tint    采样到的角标原色，压得很淡，保住"这是红色通知"的语义
///   fill    上亮下暗的乳白渐变，玻璃本体
///   sheen   左上角一团柔光 + 顶部一条高光，负责"液态"的反光感
/// 呼吸动画只动 sheen 的 opacity，不动 transform —— 角标尺寸只有十几点，
/// 缩放 4% 就是 0.6px，肉眼看不出，却会让 SpringBoard 每帧重排图标网格。
@interface AxsBadgeGlassView : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) CALayer *tintLayer;
@property (nonatomic, strong) CAGradientLayer *fillLayer;
@property (nonatomic, strong) CAGradientLayer *sheenLayer;
- (void)axs_applyTint:(UIColor *)color;
- (void)axs_setBreathing:(BOOL)on;
@end

@implementation AxsBadgeGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.layer.masksToBounds = YES;

    if ([[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_badgeBlur]) {
        // SystemUltraThinMaterial 是全系统最薄的一档，在小面积上几乎不增加功耗：
        // 模糊只在一块十几点的圆里做，而且角标是静止的，不滚动就不重算。
        self.blurView = [[UIVisualEffectView alloc]
                         initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        self.blurView.userInteractionEnabled = NO;
        self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.blurView];
    }

    // 之后的三个 CALayer 都挂在 self.layer 上，天然位于 blurView 的图层之上。
    self.tintLayer = [CALayer layer];
    self.tintLayer.opacity = 0.0;
    [self.layer addSublayer:self.tintLayer];

    self.fillLayer = [CAGradientLayer layer];
    self.fillLayer.startPoint = CGPointMake(0.2, 0.0);
    self.fillLayer.endPoint = CGPointMake(0.8, 1.0);
    self.fillLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.34].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.06].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.12].CGColor,
    ];
    self.fillLayer.locations = @[@0.0, @0.5, @1.0];
    [self.layer addSublayer:self.fillLayer];

    self.sheenLayer = [CAGradientLayer layer];
    self.sheenLayer.type = kCAGradientLayerRadial;
    self.sheenLayer.startPoint = CGPointMake(0.26, 0.12);
    self.sheenLayer.endPoint = CGPointMake(0.86, 0.92);
    self.sheenLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.52].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
    ];
    [self.layer addSublayer:self.sheenLayer];

    // 描边画在圆的外沿：角标只有十几点，1pt 就足够"有玻璃壳"了。
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.46].CGColor;

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = CGRectGetHeight(self.bounds) / 2.0;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.cornerRadius = radius;
    self.blurView.layer.cornerRadius = radius;
    self.blurView.clipsToBounds = YES;
    self.blurView.frame = self.bounds;
    self.tintLayer.frame = self.bounds;
    self.tintLayer.cornerRadius = radius;
    self.fillLayer.frame = self.bounds;
    self.fillLayer.cornerRadius = radius;
    self.sheenLayer.frame = self.bounds;
    self.sheenLayer.cornerRadius = radius;
    [CATransaction commit];
}

- (void)axs_applyTint:(UIColor *)color {
    if (!color) {
        self.tintLayer.opacity = 0.0;
        return;
    }
    self.tintLayer.backgroundColor = color.CGColor;
    self.tintLayer.opacity = 0.30;
}

- (void)axs_setBreathing:(BOOL)on {
    if (!on) {
        [self.sheenLayer removeAnimationForKey:@"heli.badge.breath"];
        self.sheenLayer.opacity = 1.0;
        return;
    }
    if ([self.sheenLayer animationForKey:@"heli.badge.breath"]) return;

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @0.45;
    pulse.toValue = @1.0;
    pulse.duration = 1.6;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.sheenLayer addAnimation:pulse forKey:@"heli.badge.breath"];
}

@end

#pragma mark - 采样 / 还原

/// 角标底板要么是自身 backgroundColor，要么是某个子视图的 backgroundColor。
/// 纯红是因为系统按"未读数"给了个 red，我们要的是那个颜色本身，不是它盖住玻璃。
static UIColor *AxsBadgeSampleBackground(UIView *badge) {
    UIColor *color = badge.backgroundColor;
    if (color && CGColorGetAlpha(color.CGColor) > 0.05) return color;

    UIView *best = nil;
    CGFloat bestArea = 0.0;
    for (UIView *sub in badge.subviews) {
        if ([sub isKindOfClass:[AxsBadgeGlassView class]]) continue;
        if ([sub isKindOfClass:[UILabel class]]) continue;
        UIColor *candidate = sub.backgroundColor;
        if (!candidate || CGColorGetAlpha(candidate.CGColor) <= 0.05) continue;
        CGFloat area = CGRectGetWidth(sub.bounds) * CGRectGetHeight(sub.bounds);
        if (area > bestArea) {
            bestArea = area;
            best = sub;
        }
    }
    return best.backgroundColor;
}

static NSDictionary *AxsBadgeCaptureSnapshot(UIView *badge) {
    NSMutableArray<NSNumber *> *alphas = [NSMutableArray array];
    for (UIView *sub in badge.subviews) {
        [alphas addObject:@(sub.alpha)];
    }
    UIColor *background = badge.backgroundColor;
    id backgroundValue = background ? (id)background : (id)[NSNull null];
    return @{
        @"alphas": alphas,
        @"background": backgroundValue,
    };
}

static void AxsBadgeRestoreLook(UIView *badge) {
    NSDictionary *snapshot = objc_getAssociatedObject(badge, &kAxsBadgeSnapshotKey);
    if (!snapshot) return;

    AxsBadgeGlassView *glass = objc_getAssociatedObject(badge, &kAxsBadgeGlassKey);
    NSArray<NSNumber *> *alphas = snapshot[@"alphas"];
    NSArray<UIView *> *subviews = badge.subviews;

    // 子视图顺序可能变过，按下标还原，长度不一致就整体放开，宁可回到原生也不留半截半透明。
    if (alphas.count == subviews.count) {
        for (NSUInteger i = 0; i < subviews.count; i++) {
            UIView *sub = subviews[i];
            if (sub == glass) continue;
            sub.alpha = [alphas[i] doubleValue];
        }
    } else {
        for (UIView *sub in subviews) {
            if (sub == glass) continue;
            sub.alpha = 1.0;
        }
    }

    id background = snapshot[@"background"];
    if ([background isKindOfClass:[UIColor class]]) {
        badge.backgroundColor = background;
    } else if (background == [NSNull null]) {
        badge.backgroundColor = nil;
    }
    objc_setAssociatedObject(badge, &kAxsBadgeSnapshotKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 挂载 / 摘除

static void AxsBadgeDetach(UIView *badge) {
    if (!badge) return;
    AxsBadgeGlassView *glass = objc_getAssociatedObject(badge, &kAxsBadgeGlassKey);
    if (!glass) return;

    @try {
        [glass axs_setBreathing:NO];
        // 先还原再摘：快照里的 alpha 数组包含玻璃自己那一格，顺序必须对齐。
        AxsBadgeRestoreLook(badge);
        [glass removeFromSuperview];
        objc_setAssociatedObject(badge, &kAxsBadgeGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (gAxsBadgeAttachedCount > 0) gAxsBadgeAttachedCount -= 1;
    } @catch (NSException *exception) {
        AxsLog(@"badge: 摘除失败 %@", exception.reason);
    }
}

/// 只改属性，绝不插视图、不改层级。layoutSubviews 里只允许调它。
static void AxsBadgeReassert(UIView *badge, AxsBadgeGlassView *glass) {
    glass.frame = badge.bounds;

    double alpha = [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_badgeBackgroundAlpha];
    for (UIView *sub in badge.subviews) {
        if (sub == glass) continue;
        if ([sub isKindOfClass:[UILabel class]]) continue;
        if (fabs(sub.alpha - alpha) > 0.002) sub.alpha = (CGFloat)alpha;
    }

    // 系统会在更新未读数时把底色写回来，这里顺手再压一次。
    // alpha = 1 表示用户要的就是原生观感，别动底色。
    if (alpha < 0.999 && CGColorGetAlpha(badge.backgroundColor.CGColor) > 0.05) {
        badge.backgroundColor = [UIColor clearColor];
    }
}

static void AxsBadgeAttach(UIView *badge) {
    if (!badge || !badge.window) return;

    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    if (![config axs_liquidglass_badgeEnabled]) {
        AxsBadgeDetach(badge);
        return;
    }
    if (objc_getAssociatedObject(badge, &kAxsBadgeGlassKey)) {
        AxsBadgeReassert(badge, objc_getAssociatedObject(badge, &kAxsBadgeGlassKey));
        return;
    }

    // 尺寸防呆：角标是十几点的小圆，超出这个范围说明挂到别的东西上了。
    CGRect bounds = badge.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width < 6.0 || height < 6.0 || width > 120.0 || height > 120.0) return;

    @try {
        UIColor *sampled = AxsBadgeSampleBackground(badge);

        AxsBadgeGlassView *glass = [[AxsBadgeGlassView alloc] initWithFrame:bounds];
        [badge insertSubview:glass atIndex:0];
        objc_setAssociatedObject(badge, &kAxsBadgeGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // 快照必须在玻璃插进来之后拍：数组下标与 badge.subviews 一一对应，
        // 还原时才不会整体错位一格（玻璃在第 0 位，还原时按指针跳过）。
        objc_setAssociatedObject(badge, &kAxsBadgeSnapshotKey,
                                 AxsBadgeCaptureSnapshot(badge), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gAxsBadgeAttachedCount += 1;

        if ([config axs_liquidglass_badgeKeepColor]) {
            [glass axs_applyTint:sampled ?: [UIColor systemRedColor]];
        } else {
            [glass axs_applyTint:nil];
        }

        BOOL breathing = [config axs_liquidglass_badgeBreathing] && !UIAccessibilityIsReduceMotionEnabled();
        [glass axs_setBreathing:breathing];

        AxsBadgeReassert(badge, glass);

        if (gAxsBadgeAttachedCount <= 3) {
            AxsLog(@"badge: 挂载 %@ (%.0fx%.0f, 共 %ld)",
                   NSStringFromClass([badge class]), width, height, (long)gAxsBadgeAttachedCount);
        }
    } @catch (NSException *exception) {
        AxsLog(@"badge: 挂载失败 %@", exception.reason);
    }
}

#pragma mark - 钩子

static void (*axs_badge_orig_didMoveToWindow)(UIView *, SEL);
static void (*axs_badge_orig_layoutSubviews)(UIView *, SEL);

static void axs_badge_didMoveToWindow(UIView *self, SEL _cmd) {
    if (axs_badge_orig_didMoveToWindow) {
        axs_badge_orig_didMoveToWindow(self, _cmd);
    }
    if (!self.window) {
        AxsBadgeDetach(self);
        return;
    }
    // 延到本次 runloop 之后挂：didMoveToWindow 期间图标网格还在布局，
    // 此刻插子视图会把 SpringBoard 拽进"布局 → 插视图 → 再布局"的循环。
    __weak UIView *weakBadge = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *badge = weakBadge;
        if (!badge || !badge.window) return;
        AxsBadgeAttach(badge);
    });
}

static void axs_badge_layoutSubviews(UIView *self, SEL _cmd) {
    if (axs_badge_orig_layoutSubviews) {
        axs_badge_orig_layoutSubviews(self, _cmd);
    }
    AxsBadgeGlassView *glass = objc_getAssociatedObject(self, &kAxsBadgeGlassKey);
    if (!glass) return;
    if (objc_getAssociatedObject(self, &kAxsBadgeReassertKey)) return;

    objc_setAssociatedObject(self, &kAxsBadgeReassertKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AxsBadgeReassert(self, glass);
    objc_setAssociatedObject(self, &kAxsBadgeReassertKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 全量刷新

static void AxsBadgeWalk(UIView *view, void (^block)(UIView *)) {
    if (!view) return;
    block(view);
    for (UIView *child in view.subviews) {
        AxsBadgeWalk(child, block);
    }
}

@implementation AxsLiquidGlassBadge

+ (BOOL)axs_liquidglass_isInstalled {
    return gAxsBadgeInstalled;
}

+ (void)axs_liquidglass_refreshAll {
    if (![NSThread isMainThread]) return;

    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    BOOL enabled = [config axs_liquidglass_badgeEnabled];
    if (enabled && !gAxsBadgeInstalled) {
        [self axs_liquidglass_installHooksIfAvailable];
    }

    Class badgeClass = NSClassFromString(@"SBIconBadgeView");
    if (!badgeClass) return;

    UIApplication *application = [UIApplication sharedApplication];
    // SpringBoard 只有一个窗口场景，走 scene API 反而要处理"场景还没连上"的分支；
    // 这里保留 windows，把弃用警告就地关掉（-Werror 会把警告当错误）。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIWindow *> *windows = application.windows;
#pragma clang diagnostic pop
    for (UIWindow *window in windows) {
        AxsBadgeWalk(window, ^(UIView *view) {
            if (![view isKindOfClass:badgeClass]) return;
            if (enabled) {
                AxsBadgeAttach(view);
            } else {
                AxsBadgeDetach(view);
            }
        });
    }
}

+ (BOOL)axs_liquidglass_installHooksIfAvailable {
    if (gAxsBadgeInstalled) return YES;
    if (![[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_badgeEnabled]) {
        AxsLog(@"badge: 面板里关着，不装钩子");
        return NO;
    }

    Class badgeClass = NSClassFromString(@"SBIconBadgeView");
    if (!badgeClass) {
        AxsLog(@"badge: SBIconBadgeView 不存在，跳过");
        return NO;
    }

    MSHookMessageEx(badgeClass, @selector(didMoveToWindow),
                    (IMP)axs_badge_didMoveToWindow, (IMP *)&axs_badge_orig_didMoveToWindow);

    // layoutSubviews 只在这类自己实现时才挂：继承来的话 MSHookMessageEx 等于
    // 给 UIView 的布局路径加一段代码，波及全系统 UIView。
    BOOL layoutHooked = NO;
    if (axs_liquidglass_classImplements(badgeClass, @selector(layoutSubviews))) {
        MSHookMessageEx(badgeClass, @selector(layoutSubviews),
                        (IMP)axs_badge_layoutSubviews, (IMP *)&axs_badge_orig_layoutSubviews);
        layoutHooked = YES;
    }

    gAxsBadgeInstalled = YES;
    AxsLog(@"badge: 已挂 SBIconBadgeView（didMoveToWindow=YES layoutSubviews=%d）", layoutHooked);
    return YES;
}

@end
