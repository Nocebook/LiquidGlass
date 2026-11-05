#import "AxsLiquidGlassSurface.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassPrivate.h"

static char kAxsLiquidGlassKindKey;

static NSString *axs_liquidglass_processName(void) {
    static NSString *name;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        name = [NSProcessInfo processInfo].processName ?: @"";
    });
    return name;
}

@implementation AxsLiquidGlassSurface

+ (BOOL)axs_liquidglass_isWidgetProcess {
    static BOOL isWidget;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *name = axs_liquidglass_processName();
        // 小组件渲染在独立进程里，快照流程对视图层级的改动异常敏感。
        isWidget = [name isEqualToString:@"chronod"] ||
                   [name containsString:@"WidgetRenderer"] ||
                   [name containsString:@"ClockAngel"];
    });
    return isWidget;
}

+ (AxsLiquidGlassSurfaceKind)axs_liquidglass_kindForView:(UIView *)view {
    if (!view) return AxsLiquidGlassSurfaceKindNone;
    if ([self axs_liquidglass_isWidgetProcess]) return AxsLiquidGlassSurfaceKindWidget;

    NSNumber *cached = objc_getAssociatedObject(view, &kAxsLiquidGlassKindKey);
    if ([cached isKindOfClass:[NSNumber class]]) {
        return (AxsLiquidGlassSurfaceKind)[cached integerValue];
    }

    AxsLiquidGlassSurfaceKind kind = [self axs_liquidglass_kindForClassChain:view];
    if (kind != AxsLiquidGlassSurfaceKindNone) {
        objc_setAssociatedObject(view, &kAxsLiquidGlassKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return kind;
    }
    // 兜底分类不进缓存：视图此时可能还没挂进真正的容器，等下一次再判断。
    return [self axs_liquidglass_fallbackKind];
}

+ (AxsLiquidGlassSurfaceKind)axs_liquidglass_fallbackKind {
    NSString *process = axs_liquidglass_processName();
    if ([process containsString:@"MediaRemote"]) return AxsLiquidGlassSurfaceKindAlert;
    // SpringBoard 里"匹配不到"的视图一律不处理。
    // 旧版本这里默认返回 Home，等于把锁屏、状态栏、墙纸这类没人认识的表面
    // 全按"Dock 玻璃"铺膜加网格 —— 锁屏上滑卡死就是这么来的。
    // 主屏该有的入口都由 dock/folder/sbicon/homescreen 关键字命中，不需要兜底。
    return AxsLiquidGlassSurfaceKindNone;
}

+ (AxsLiquidGlassSurfaceKind)axs_liquidglass_kindForClassChain:(UIView *)view {
    // 从视图自身往上走，越靠近的祖先越能说明这块表面是什么。
    UIView *current = view;
    for (NSInteger depth = 0; current && depth < 20; depth++) {
        NSString *name = NSStringFromClass([current class]).lowercaseString;
        if ([name containsString:@"widget"] || [name containsString:@"chrono"]) {
            return AxsLiquidGlassSurfaceKindWidget;
        }
        if ([name containsString:@"keyboard"] || [name containsString:@"predictive"]) {
            return AxsLiquidGlassSurfaceKindKeyboard;
        }
        // 锁屏必须排在 alert 之前：CSCoverSheetViewController / CSCombinedListViewController
        // 这些类名同时能命中下面的 "coversheet"，误判成弹窗就会去改解锁动画的模糊。
        if ([name containsString:@"lockscreen"] || [name containsString:@"lockview"] ||
            [name containsString:@"cslock"] || [name containsString:@"cscombined"] ||
            [name containsString:@"coversheet"] || [name containsString:@"sbcover"] ||
            [name containsString:@"coverSheetHost"]) {
            return AxsLiquidGlassSurfaceKindLockScreen;
        }
        if ([name containsString:@"controlcenter"] || [name containsString:@"ccmodule"] ||
            [name containsString:@"moduleview"] || [name containsString:@"sbcc"]) {
            return AxsLiquidGlassSurfaceKindControlCenter;
        }
        if ([name containsString:@"notification"] || [name containsString:@"banner"] ||
            [name containsString:@"contextmenu"] ||
            [name containsString:@"platter"] || [name containsString:@"alertcontroller"]) {
            return AxsLiquidGlassSurfaceKindAlert;
        }
        if ([name containsString:@"dock"] || [name containsString:@"folder"] ||
            [name containsString:@"sbicon"] || [name containsString:@"homescreen"]) {
            return AxsLiquidGlassSurfaceKindHome;
        }
        current = current.superview;
    }
    return AxsLiquidGlassSurfaceKindNone;
}

+ (NSString *)axs_liquidglass_scopeForKey:(AxsLiquidGlassSurfaceKind)kind {
    switch (kind) {
        case AxsLiquidGlassSurfaceKindHome: return @"home";
        case AxsLiquidGlassSurfaceKindControlCenter: return @"controlCenter";
        case AxsLiquidGlassSurfaceKindAlert: return @"alerts";
        case AxsLiquidGlassSurfaceKindKeyboard: return @"keyboard";
        default: return nil;
    }
}

+ (BOOL)axs_liquidglass_isWidgetBlockedForView:(UIView *)view {
    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    NSMutableString *haystack = [NSMutableString string];
    UIView *current = view;
    for (NSInteger depth = 0; current && depth < 12; depth++) {
        for (NSString *key in @[@"extensionBundleIdentifier", @"containerBundleIdentifier",
                                @"widgetIdentifier", @"bundleIdentifier"]) {
            id value = nil;
            @try {
                value = [current valueForKey:key];
            } @catch (NSException *exception) {
                (void)exception;
                value = nil;
            }
            if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
                [haystack appendFormat:@" %@", [(NSString *)value lowercaseString]];
            }
        }
        current = current.superview;
    }
    return [config axs_liquidglass_isWidgetIdentifierBlocked:haystack];
}

+ (BOOL)axs_liquidglass_shouldHandleView:(UIView *)view kind:(AxsLiquidGlassSurfaceKind)kind {
    if (kind == AxsLiquidGlassSurfaceKindNone) return NO;
    // 锁屏的模糊半径是解锁动画的时间轴：上滑过程中系统每帧都会重设一次，
    // 任何改写都会把动画拖成幻灯片。这一类完全交给系统原样渲染。
    if (kind == AxsLiquidGlassSurfaceKindLockScreen) return NO;

    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    if (![config axs_liquidglass_isEnabled]) return NO;

    if (kind == AxsLiquidGlassSurfaceKindWidget) {
        // 完全跳过模式下连模糊参数都不碰，留给系统原样渲染。
        if ([config axs_liquidglass_widgetMode] == 0) return NO;
        return ![self axs_liquidglass_isWidgetBlockedForView:view];
    }

    NSString *scope = [self axs_liquidglass_scopeForKey:kind];
    return scope ? [config axs_liquidglass_scopeEnabled:scope] : YES;
}

+ (BOOL)axs_liquidglass_allowsDecorativeLayersForKind:(AxsLiquidGlassSurfaceKind)kind {
    if (kind == AxsLiquidGlassSurfaceKindWidget) {
        // widget 进程内存只有 30~50MB，加自绘图层是被杀进程的常见诱因。
        // 默认的模式 2 用零 layer 的描边（layer.borderWidth），只有明确选到模式 3 才允许加图层。
        return [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_widgetMode] >= 3;
    }
    if (kind == AxsLiquidGlassSurfaceKindKeyboard) return NO;  // 键盘上叠高光会遮挡候选字
    return YES;
}

@end
