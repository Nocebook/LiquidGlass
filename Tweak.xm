// Glassify 8.0.1 — 稳定版：只做通知角标玻璃 + 未读呼吸动画
//
// 8.0.0 在真机上进了安全模式，原因是两类风险：
//   1) 在 layoutSubviews 里 insertSubview —— 触发递归布局，看门狗杀进程
//   2) MSHookMessageEx 之后 orig 可能为 NULL，仍被调用 —— 空指针
//
// 这一版的处理：
//   - 去掉 Dock / 文件夹 / 控制中心三个挂钩（它们都在系统布局回调里插视图）
//   - 角标只在 didMoveToWindow 时异步挂载，绝不在 layoutSubviews 里插入
//   - layoutSubviews 只做「已存在则改 frame」，不新增视图
//   - 所有 hook 先判 orig，所有挂载逻辑包 @try

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <math.h>
#import <substrate.h>

#define GS_DOMAIN @"com.heli.liquid"
#define GS_RELOAD "com.heli.liquid/reload"
#define GS_DUMP   "com.heli.liquid/dump"

static const NSInteger GSGlassTag = 0x6701;

#pragma mark - 偏好

static id GSPref(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)GS_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)GS_DOMAIN);
    return v ? (__bridge_transfer id)v : nil;
}

static BOOL GSBool(NSString *key, BOOL fallback) {
    id v = GSPref(key);
    return v ? [v boolValue] : fallback;
}

static double GSDouble(NSString *key, double fallback) {
    id v = GSPref(key);
    return v ? [v doubleValue] : fallback;
}

static BOOL GSEnabled(void) {
    return GSBool(@"Enabled", YES) && GSBool(@"Badge", YES);
}

#pragma mark - 角标玻璃

@interface GSBadgeGlassView : UIView
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) CAGradientLayer *sheen;
@property (nonatomic, strong) CALayer *tint;
- (void)setBreathing:(BOOL)on;
@end

@implementation GSBadgeGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    self.blur = [[UIVisualEffectView alloc]
                 initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    self.blur.userInteractionEnabled = NO;
    self.blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.blur];

    self.tint = [CALayer layer];
    self.tint.opacity = 0.0;
    [self.layer addSublayer:self.tint];

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

- (void)setBreathing:(BOOL)on {
    if (!on) {
        [self.layer removeAnimationForKey:@"gs.breath"];
        [self.sheen removeAnimationForKey:@"gs.breathSheen"];
        self.layer.transform = CATransform3DIdentity;
        self.sheen.opacity = 1.0;
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
    [self.layer addAnimation:scale forKey:@"gs.breath"];

    CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"opacity"];
    glow.fromValue = @0.55;
    glow.toValue = @1.0;
    glow.duration = 1.5;
    glow.autoreverses = YES;
    glow.repeatCount = HUGE_VALF;
    glow.timingFunction = ease;
    [self.sheen addAnimation:glow forKey:@"gs.breathSheen"];
}

@end

#pragma mark - 挂载 / 摘除

static UIColor *GSBadgeDimBackground(UIView *badge, CGFloat alpha) {
    UIColor *found = nil;
    for (UIView *sub in badge.subviews) {
        if (sub.tag == GSGlassTag) continue;
        if ([sub isKindOfClass:[UILabel class]]) continue;
        if (!found && sub.backgroundColor) found = sub.backgroundColor;
        sub.alpha = alpha;
    }
    return found;
}

static void GSBadgeRestoreBackground(UIView *badge) {
    for (UIView *sub in badge.subviews) {
        if (sub.tag == GSGlassTag) continue;
        if ([sub isKindOfClass:[UILabel class]]) continue;
        sub.alpha = 1.0;
    }
}

static void GSDetachBadge(UIView *badge) {
    UIView *glass = [badge viewWithTag:GSGlassTag];
    if (!glass) return;
    [glass removeFromSuperview];
    GSBadgeRestoreBackground(badge);
}

static void GSAttachBadge(UIView *badge) {
    if (!badge) return;
    if (!GSEnabled()) return;
    if (CGRectGetWidth(badge.bounds) < 4.0 || CGRectGetHeight(badge.bounds) < 4.0) return;
    if ([badge viewWithTag:GSGlassTag]) return;

    @try {
        GSBadgeGlassView *glass = [[GSBadgeGlassView alloc] initWithFrame:badge.bounds];
        glass.tag = GSGlassTag;
        [badge insertSubview:glass atIndex:0];

        UIColor *original = GSBadgeDimBackground(badge, GSDouble(@"BadgeBackgroundAlpha", 0.15));
        if (GSBool(@"BadgeKeepColor", YES)) {
            [glass applyTint:original ?: [UIColor systemRedColor]];
        }
        [glass setBreathing:GSBool(@"BadgeBreathing", YES) &&
                            !UIAccessibilityIsReduceMotionEnabled()];

        NSLog(@"[Glassify] badge %@ (%.0fx%.0f)",
              NSStringFromClass([badge class]), badge.bounds.size.width, badge.bounds.size.height);
    } @catch (NSException *e) {
        NSLog(@"[Glassify] attach failed: %@", e.reason);
    }
}

#pragma mark - 调试

static void GSDumpNode(UIView *view, int depth) {
    if (!view || depth > 12) return;
    NSMutableString *pad = [NSMutableString string];
    for (int i = 0; i < depth; i++) [pad appendString:@"  "];
    NSLog(@"[Glassify] %@%@ %@", pad, NSStringFromClass([view class]),
          NSStringFromCGRect(view.frame));
    for (UIView *child in view.subviews) {
        GSDumpNode(child, depth + 1);
    }
}

static void GSDumpTree(void) {
    NSLog(@"[Glassify] ===== tree begin =====");
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        GSDumpNode(window, 0);
    }
    NSLog(@"[Glassify] ===== tree end =====");
}

#pragma mark - 钩子

// didMoveToWindow：只在这里挂载，且延到本次 runloop 之后，避免在布局过程中改层级
static void (*orig_badge_didMoveToWindow)(UIView *, SEL);

static void hook_badge_didMoveToWindow(UIView *self, SEL _cmd) {
    if (orig_badge_didMoveToWindow) {
        orig_badge_didMoveToWindow(self, _cmd);
    }

    __weak UIView *weakBadge = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *badge = weakBadge;
        if (!badge || !badge.window) return;
        GSAttachBadge(badge);
    });
}

// layoutSubviews：绝不新增视图，只调整已存在的玻璃层
static void (*orig_badge_layoutSubviews)(UIView *, SEL);

static void hook_badge_layoutSubviews(UIView *self, SEL _cmd) {
    if (orig_badge_layoutSubviews) {
        orig_badge_layoutSubviews(self, _cmd);
    }

    UIView *glass = [self viewWithTag:GSGlassTag];
    if (glass) {
        glass.frame = self.bounds;
    }
}

#pragma mark - 刷新

static void GSRefreshAll(void) {
    BOOL on = GSEnabled();

    @try {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count) {
                UIView *view = stack.lastObject;
                [stack removeLastObject];

                if ([view isKindOfClass:[GSBadgeGlassView class]]) {
                    UIView *host = view.superview;
                    if (!on && host) {
                        [view removeFromSuperview];
                        GSBadgeRestoreBackground(host);
                    } else {
                        [(GSBadgeGlassView *)view setBreathing:
                            GSBool(@"BadgeBreathing", YES) && !UIAccessibilityIsReduceMotionEnabled()];
                    }
                }

                [stack addObjectsFromArray:view.subviews];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[Glassify] refresh failed: %@", e.reason);
    }
}

// 8.0.2：默认不挂任何钩子。装上后先确认不崩，再在设置里逐个打开，
// 就能精确定位是哪一个 hook 引起安全模式。
%ctor {
    NSLog(@"[Glassify] 8.0.2 loaded (hooks are opt-in)");

    static int reloadToken = 0;
    notify_register_dispatch(GS_RELOAD, &reloadToken, dispatch_get_main_queue(), ^(int token) {
        GSRefreshAll();
    });

    static int dumpToken = 0;
    notify_register_dispatch(GS_DUMP, &dumpToken, dispatch_get_main_queue(), ^(int token) {
        if (GSBool(@"DebugTree", NO)) GSDumpTree();
    });

    if (!GSBool(@"HooksEnabled", NO)) {
        NSLog(@"[Glassify] hooks disabled (HooksEnabled=NO)");
        return;
    }

    Class badge = objc_getClass("SBIconBadgeView");
    NSLog(@"[Glassify] SBIconBadgeView = %@", badge ? @"found" : @"MISSING");
    if (!badge) return;

    if (GSBool(@"HookMove", NO)) {
        MSHookMessageEx(badge, @selector(didMoveToWindow),
                        (IMP)hook_badge_didMoveToWindow,
                        (IMP *)&orig_badge_didMoveToWindow);
        NSLog(@"[Glassify] hooked didMoveToWindow");
    }

    if (GSBool(@"HookLayout", NO)) {
        MSHookMessageEx(badge, @selector(layoutSubviews),
                        (IMP)hook_badge_layoutSubviews,
                        (IMP *)&orig_badge_layoutSubviews);
        NSLog(@"[Glassify] hooked layoutSubviews");
    }
}
