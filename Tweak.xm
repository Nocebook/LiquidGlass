// Heli — 液态玻璃效果框架（独立实现，不含任何第三方代码）
//
// 目标机型：iPhone 14 Pro / iOS 16.3 / Dopamine (roothide)
// v0.2：通知角标玻璃（SBIconBadgeView）+ Dock / 文件夹 / 控制中心
//
// 每个作用位置独立开关，类名找不到就安静跳过，不会崩。
// 打不开效果时打开「调试：导出视图树」，用 Console / idevicesyslog 看
// [Heli] 开头的日志，把类名和层级发我，逐个精确接管。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <math.h>
#import <substrate.h>

#define HL_DOMAIN @"com.heli.liquid"
#define HL_RELOAD "com.heli.liquid/reload"
#define HL_DUMP   "com.heli.liquid/dump"

static const NSInteger HLGlassTag = 0x6701;
static const NSInteger HLBadgeGlassTag = 0x6702;

#pragma mark - 偏好读取

static id HLPref(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)HL_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)HL_DOMAIN);
    return v ? (__bridge_transfer id)v : nil;
}

static BOOL HLBool(NSString *key, BOOL fallback) {
    id v = HLPref(key);
    return v ? [v boolValue] : fallback;
}

static double HLDouble(NSString *key, double fallback) {
    id v = HLPref(key);
    return v ? [v doubleValue] : fallback;
}

#pragma mark - 通用玻璃层

@interface HLGlassView : UIView
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) CAGradientLayer *specular;
@end

@implementation HLGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    self.blur = [[UIVisualEffectView alloc]
                 initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    self.blur.userInteractionEnabled = NO;
    self.blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.blur];

    self.specular = [CAGradientLayer layer];
    self.specular.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.26].CGColor,
                             (id)[UIColor colorWithWhite:1.0 alpha:0.00].CGColor];
    self.specular.startPoint = CGPointMake(0.0, 0.0);
    self.specular.endPoint = CGPointMake(0.0, 0.55);
    [self.layer addSublayer:self.specular];

    self.layer.borderWidth = 0.8;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.specular.frame = self.bounds;
    [CATransaction commit];
}

- (void)applyRadius:(CGFloat)radius {
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.blur.layer.cornerRadius = radius;
    self.blur.layer.cornerCurve = kCACornerCurveContinuous;
    self.blur.clipsToBounds = YES;
}

@end

#pragma mark - 角标玻璃层

@interface HLBadgeGlassView : UIView
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) CAGradientLayer *sheen;
@property (nonatomic, strong) CALayer *tint;
- (void)setBreathing:(BOOL)on;
@end

@implementation HLBadgeGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // 角标很小，用最薄的一档材质，避免糊成一团
    self.blur = [[UIVisualEffectView alloc]
                 initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    self.blur.userInteractionEnabled = NO;
    self.blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.blur];

    // 角标原色染色（红/绿），叠在模糊之上
    self.tint = [CALayer layer];
    self.tint.opacity = 0.0;
    [self.layer addSublayer:self.tint];

    // 上亮下暗的玻璃高光
    self.sheen = [CAGradientLayer layer];
    self.sheen.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.48].CGColor,
                          (id)[UIColor colorWithWhite:1.0 alpha:0.06].CGColor,
                          (id)[UIColor colorWithWhite:0.0 alpha:0.16].CGColor];
    self.sheen.locations = @[@0.0, @0.55, @1.0];
    self.sheen.startPoint = CGPointMake(0.5, 0.0);
    self.sheen.endPoint = CGPointMake(0.5, 1.0);
    [self.layer addSublayer:self.sheen];

    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.42].CGColor;

    return self;
}

- (void)applyTint:(UIColor *)color {
    if (!color) {
        self.tint.opacity = 0.0;
        return;
    }
    self.tint.backgroundColor = color.CGColor;
    self.tint.opacity = 0.30;
}

// 未读呼吸：玻璃层轻微放大 + 高光提亮，数字不动，所以不会晃眼睛。
// 用 CAAnimation 交给渲染进程跑，不占 CPU、不占主线程。
- (void)setBreathing:(BOOL)on {
    if (!on) {
        [self.layer removeAnimationForKey:@"gs.breath"];
        [self.sheen removeAnimationForKey:@"gs.breathSheen"];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.layer.transform = CATransform3DIdentity;
        self.sheen.opacity = 1.0;
        [CATransaction commit];
        return;
    }

    if ([self.layer animationForKey:@"gs.breath"]) return;

    CAMediaTimingFunction *ease =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = @1.0;
    scale.toValue = @1.045;
    scale.duration = 1.5;
    scale.autoreverses = YES;
    scale.repeatCount = HUGE_VALF;
    scale.timingFunction = ease;
    scale.removedOnCompletion = NO;
    [self.layer addAnimation:scale forKey:@"gs.breath"];

    CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"opacity"];
    glow.fromValue = @0.55;
    glow.toValue = @1.0;
    glow.duration = 1.5;
    glow.autoreverses = YES;
    glow.repeatCount = HUGE_VALF;
    glow.timingFunction = ease;
    glow.removedOnCompletion = NO;
    [self.sheen addAnimation:glow forKey:@"gs.breathSheen"];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = CGRectGetHeight(self.bounds) / 2.0;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.cornerRadius = radius;
    self.blur.layer.cornerRadius = radius;
    self.blur.clipsToBounds = YES;
    self.tint.frame = self.bounds;
    self.tint.cornerRadius = radius;
    self.sheen.frame = self.bounds;
    self.sheen.cornerRadius = radius;
    [CATransaction commit];
}

@end

#pragma mark - 装饰：容器

static void HLDecorate(UIView *host, NSString *switchKey, BOOL clearHostBackground) {
    if (!host) return;
    if (!HLBool(@"Enabled", YES)) return;
    if (switchKey && !HLBool(switchKey, YES)) return;
    if (CGRectGetWidth(host.bounds) < 1.0 || CGRectGetHeight(host.bounds) < 1.0) return;

    CGSize size = host.bounds.size;
    if (size.width > 4000.0 || size.height > 4000.0) return;

    HLGlassView *existing = (HLGlassView *)[host viewWithTag:HLGlassTag];
    if (existing) {
        [existing applyRadius:HLDouble(@"CornerRadius", 28.0)];
        existing.hidden = NO;
        return;
    }

    HLGlassView *glass = [[HLGlassView alloc] initWithFrame:host.bounds];
    glass.tag = HLGlassTag;
    [glass applyRadius:HLDouble(@"CornerRadius", 28.0)];

    if (HLBool(@"AboveContent", NO)) {
        [host addSubview:glass];
    } else {
        [host insertSubview:glass atIndex:0];
    }

    if (clearHostBackground) {
        host.backgroundColor = [UIColor clearColor];
    }

    NSLog(@"[Heli] decorated %@ (%.0fx%.0f)",
          NSStringFromClass([host class]), size.width, size.height);
}

#pragma mark - 装饰：通知角标

// 角标里除了数字，其余子视图都是"底板"，把它们调淡让玻璃透出来
static UIColor *HLBadgeDimBackground(UIView *badge, CGFloat alpha) {
    UIColor *found = nil;
    for (UIView *sub in badge.subviews) {
        if (sub.tag == HLBadgeGlassTag) continue;
        if ([sub isKindOfClass:[UILabel class]]) continue;

        if (!found && sub.backgroundColor) found = sub.backgroundColor;
        sub.alpha = alpha;
    }
    return found;
}

static void HLBadgeRestoreBackground(UIView *badge) {
    for (UIView *sub in badge.subviews) {
        if (sub.tag == HLBadgeGlassTag) continue;
        if ([sub isKindOfClass:[UILabel class]]) continue;
        sub.alpha = 1.0;
    }
}

static void HLDecorateBadge(UIView *badge) {
    if (!badge) return;

    BOOL enabled = HLBool(@"Enabled", YES) && HLBool(@"Badge", YES);
    BOOL breathe = enabled && HLBool(@"BadgeBreathing", YES) &&
                   !UIAccessibilityIsReduceMotionEnabled();

    HLBadgeGlassView *glass = (HLBadgeGlassView *)[badge viewWithTag:HLBadgeGlassTag];

    if (!enabled) {
        if (glass) {
            [glass removeFromSuperview];
            HLBadgeRestoreBackground(badge);
        }
        return;
    }

    if (CGRectGetWidth(badge.bounds) < 4.0 || CGRectGetHeight(badge.bounds) < 4.0) return;

    if (glass) {
        [glass setBreathing:breathe];
        [glass setNeedsLayout];
        return;
    }

    glass = [[HLBadgeGlassView alloc] initWithFrame:badge.bounds];
    glass.tag = HLBadgeGlassTag;
    [badge insertSubview:glass atIndex:0];

    UIColor *originalColor = HLBadgeDimBackground(badge, HLDouble(@"BadgeBackgroundAlpha", 0.15));

    if (HLBool(@"BadgeKeepColor", YES)) {
        [glass applyTint:originalColor ?: [UIColor systemRedColor]];
    }

    [glass setBreathing:breathe];

    // 出现时弹一下，接近系统的"液态"手感
    glass.transform = CGAffineTransformMakeScale(0.72, 0.72);
    [UIView animateWithDuration:0.30
                          delay:0.0
         usingSpringWithDamping:0.62
          initialSpringVelocity:0.7
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        glass.transform = CGAffineTransformIdentity;
    } completion:nil];

    if (HLBool(@"DebugTree", NO)) {
        NSLog(@"[Heli] badge %@ (%.0fx%.0f)", NSStringFromClass([badge class]),
              badge.bounds.size.width, badge.bounds.size.height);
    }
}

#pragma mark - 调试：导出视图树

static void HLDumpNode(UIView *view, int depth) {
    if (!view || depth > 14) return;
    NSMutableString *pad = [NSMutableString string];
    for (int i = 0; i < depth; i++) [pad appendString:@"  "];
    NSLog(@"[Heli] %@%@ %@", pad, NSStringFromClass([view class]),
          NSStringFromCGRect(view.frame));
    for (UIView *child in view.subviews) {
        HLDumpNode(child, depth + 1);
    }
}

// 取窗口列表：优先走 windowScene，避免 deprecated 警告；
// 拿不到时兜底回退到老的 UIApplication.windows。
static NSArray<UIWindow *> *HLAllWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    if (windows.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:[UIApplication sharedApplication].windows];
#pragma clang diagnostic pop
    }
    return windows;
}

static void HLDumpTree(void) {
    NSLog(@"[Heli] ===== tree begin =====");
    for (UIWindow *window in HLAllWindows()) {
        HLDumpNode(window, 0);
    }
    NSLog(@"[Heli] ===== tree end =====");
}

#pragma mark - 各作用位置的适配器

static void (*orig_SBIconBadgeView_layoutSubviews)(UIView *, SEL);

static void hook_SBIconBadgeView_layoutSubviews(UIView *self, SEL _cmd) {
    orig_SBIconBadgeView_layoutSubviews(self, _cmd);
    HLDecorateBadge(self);
}

static void (*orig_SBDockView_layoutSubviews)(UIView *, SEL);

static void hook_SBDockView_layoutSubviews(UIView *self, SEL _cmd) {
    orig_SBDockView_layoutSubviews(self, _cmd);
    HLDecorate(self, @"Dock", NO);
}

static void (*orig_SBFolderBG_didMoveToWindow)(UIView *, SEL);

static void hook_SBFolderBG_didMoveToWindow(UIView *self, SEL _cmd) {
    orig_SBFolderBG_didMoveToWindow(self, _cmd);
    HLDecorate(self, @"Folder", YES);
}

static void (*orig_CC_viewDidAppear)(UIViewController *, SEL, BOOL);

static void hook_CC_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    orig_CC_viewDidAppear(self, _cmd, animated);
    HLDecorate(self.view, @"ControlCenter", NO);
}

#pragma mark - 安装

static void HLRefreshAll(void) {
    BOOL badgeOn = HLBool(@"Enabled", YES) && HLBool(@"Badge", YES);

    for (UIWindow *window in HLAllWindows()) {
        NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
        while (stack.count) {
            UIView *view = stack.lastObject;
            [stack removeLastObject];

            if ([view isKindOfClass:[HLGlassView class]]) {
                [(HLGlassView *)view applyRadius:HLDouble(@"CornerRadius", 28.0)];
            } else if ([view isKindOfClass:[HLBadgeGlassView class]]) {
                UIView *host = view.superview;
                if (!badgeOn && host) {
                    [view removeFromSuperview];
                    HLBadgeRestoreBackground(host);
                } else {
                    BOOL breathe = badgeOn && HLBool(@"BadgeBreathing", YES) &&
                                   !UIAccessibilityIsReduceMotionEnabled();
                    [(HLBadgeGlassView *)view setBreathing:breathe];
                    [view setNeedsLayout];
                }
            }

            [stack addObjectsFromArray:view.subviews];
        }
    }
}

%ctor {
    Class badge = objc_getClass("SBIconBadgeView");
    if (badge) {
        MSHookMessageEx(badge, @selector(layoutSubviews),
                        (IMP)hook_SBIconBadgeView_layoutSubviews,
                        (IMP *)&orig_SBIconBadgeView_layoutSubviews);
    }

    Class dock = objc_getClass("SBDockView");
    if (dock) {
        MSHookMessageEx(dock, @selector(layoutSubviews),
                        (IMP)hook_SBDockView_layoutSubviews,
                        (IMP *)&orig_SBDockView_layoutSubviews);
    }

    Class folderBG = objc_getClass("SBFolderControllerBackgroundView");
    if (folderBG) {
        MSHookMessageEx(folderBG, @selector(didMoveToWindow),
                        (IMP)hook_SBFolderBG_didMoveToWindow,
                        (IMP *)&orig_SBFolderBG_didMoveToWindow);
    }

    Class cc = objc_getClass("CCUIModularControlCenterOverlayViewController");
    if (cc) {
        MSHookMessageEx(cc, @selector(viewDidAppear:),
                        (IMP)hook_CC_viewDidAppear,
                        (IMP *)&orig_CC_viewDidAppear);
    }

    NSLog(@"[Heli] hooks: badge=%@ dock=%@ folder=%@ controlCenter=%@",
          badge ? @"yes" : @"no", dock ? @"yes" : @"no",
          folderBG ? @"yes" : @"no", cc ? @"yes" : @"no");

    static int reloadToken = 0;
    notify_register_dispatch(HL_RELOAD, &reloadToken, dispatch_get_main_queue(), ^(int token) {
        HLRefreshAll();
    });

    static int dumpToken = 0;
    notify_register_dispatch(HL_DUMP, &dumpToken, dispatch_get_main_queue(), ^(int token) {
        if (HLBool(@"DebugTree", NO)) HLDumpTree();
    });
}
