#import "AxsLiquidGlassBackdrop.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLens.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassMesh.h"
#import "AxsLiquidGlassPrivate.h"
#import "AxsLiquidGlassSurface.h"

#import <substrate.h>
#import <QuartzCore/QuartzCore.h>
#include <string.h>

static char kAxsLiquidGlassBackdropAppliedKey;
static char kAxsLiquidGlassBackdropKeyboardKey;

static void (*axs_liquidglass_origDidMoveToSuperview)(id, SEL);
static void (*axs_liquidglass_origLayoutSubviews)(id, SEL);

static NSInteger gAxsBackdropAppliedCount = 0;
static NSInteger gAxsBackdropSkippedCount = 0;
static BOOL gAxsBackdropLogged = NO;

/// 应用参数签名。用 C 结构体而不是格式化字符串：
/// layoutSubviews 是逐帧回调，每次拼一个 NSString 会持续产生临时对象，
/// 滚动时的内存分配压力基本都来自这里。
typedef struct {
    float rim;
    float fill;
    float specular;
    float mesh;
    float radius;
    int perfMode;
} AxsBackdropSignature;

@interface AxsLiquidGlassBackdrop ()
+ (void)axs_liquidglass_clear:(UIView *)view;
@end

static BOOL axs_liquidglass_isWidgetProcess(void) {
    // 进程名判定只做一次：每次 layout 都去问 NSProcessInfo 会分配字符串。
    return [AxsLiquidGlassSurface axs_liquidglass_isWidgetProcess];
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
    // 结果缓存在视图上：这个判定要往上走 12 层、每层都做一次类名小写化，
    // 在 App 里每一个背景模糊都是"不是键盘"，每次布局都重算纯属浪费。
    // 视图换过父级时由 didMoveToSuperview 清掉缓存重新判定。
    NSNumber *cached = objc_getAssociatedObject(view, &kAxsLiquidGlassBackdropKeyboardKey);
    if (cached) return cached.boolValue;

    BOOL found = NO;
    UIView *current = view;
    for (NSInteger depth = 0; current && depth < 12; depth++) {
        NSString *name = NSStringFromClass([current class]).lowercaseString;
        if ([name containsString:@"keyboard"] || [name containsString:@"predictive"]) {
            found = YES;
            break;
        }
        current = current.superview;
    }
    objc_setAssociatedObject(view, &kAxsLiquidGlassBackdropKeyboardKey, @(found),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return found;
}

static void axs_liquidglass_hookDidMoveToSuperview(id self, SEL _cmd) {
    if (axs_liquidglass_origDidMoveToSuperview) {
        axs_liquidglass_origDidMoveToSuperview(self, _cmd);
    }
    objc_setAssociatedObject((id)self, &kAxsLiquidGlassBackdropKeyboardKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

    const AxsLiquidGlassParams *params = AxsLiquidGlassParamsGet();
    AxsLiquidGlassParams current = *params;   // 一次拷出来，后面全用栈上的值

    if (!current.enabled) {
        [self axs_liquidglass_clear:view];
        return;
    }

    double rim = current.rimStrength;
    double fill = current.fillAlpha;
    double specular = current.specularStrength;
    double mesh = current.meshStrength;
    NSInteger perfMode = current.perfMode;

    if (rim <= 0.001 && fill <= 0.001 && specular <= 0.001) {
        [self axs_liquidglass_clear:view];
        return;
    }

    CGFloat radius = axs_liquidglass_effectiveRadius(view);

    // 签名比对放在最前面（除了零成本的类判断）：参数和几何都没变就直接返回，
    // 不再做键盘祖先遍历、不再拼字符串、也不重新算半径。
    // 比对用 memcmp 而不是 -isEqual：这条路径每帧都会走，不能有任何对象分配。
    AxsBackdropSignature signature;
    signature.rim = (float)rim;
    signature.fill = (float)fill;
    signature.specular = (float)specular;
    signature.mesh = (float)mesh;
    signature.radius = (float)radius;
    signature.perfMode = (int)perfMode;
    NSData *previous = objc_getAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey);
    if ([previous isKindOfClass:[NSData class]] &&
        previous.length == sizeof(signature) &&
        memcmp(previous.bytes, &signature, sizeof(signature)) == 0) {
        [AxsLiquidGlassLens axs_liquidglass_layoutView:view radius:radius];
        return;
    }

    // 键盘判定要往上走 12 层，所以放在签名命中之后：常规表面走不到这里。
    if (!current.keyboardScope && axs_liquidglass_isKeyboardSurface(view)) return;

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

    objc_setAssociatedObject(view, &kAxsLiquidGlassBackdropAppliedKey,
                             [NSData dataWithBytes:&signature length:sizeof(signature)],
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
