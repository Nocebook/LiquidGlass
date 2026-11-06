#import "AxsLiquidGlassIslandDriver.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassGuard.h"
#import "AxsLiquidGlassLens.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassMesh.h"
#import "AxsLiquidGlassPrivate.h"

#include <string.h>

static __weak UIView *gAxsIslandGlassContainer;
static BOOL gAxsIslandGlassApplied = NO;
static BOOL gAxsIslandGlassNoteLogged = NO;

/// 上一次成功挂载时的参数快照。几何、圆角、参数都没变就不再碰图层 ——
/// 灵动岛是轮询刷新的，每轮都重设一次玻璃膜会提交一次 CA 事务、
/// 把胶囊底重新合成一遍，一天下来是几万次完全多余的重绘。
typedef struct {
    float width;
    float height;
    float radius;
    float rim;
    float fill;
    float specular;
    float mesh;
    int perfMode;
} AxsIslandSignature;

static AxsIslandSignature gAxsIslandSignature;
static BOOL gAxsIslandHasSignature = NO;

#pragma mark - 命名判定

static BOOL AxsIslandGlassNameMatches(NSString *name) {
    if (name.length == 0) return NO;
    return [name rangeOfString:@"aperture" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

/// 这些宿主树里也会出现名字带 aperture 的视图（锁屏收起态的灵动岛就是），
/// 但它们不是本体容器。往里面挂玻璃会连带把锁屏的模糊底一起改掉。
static BOOL AxsIslandGlassIsForeignHost(NSString *className) {
    NSString *lower = [className lowercaseString];
    return [lower containsString:@"lockscreen"] || [lower containsString:@"cover"] ||
           [lower containsString:@"homescreen"] || [lower containsString:@"switcher"] ||
           [lower containsString:@"wallpaper"] || [lower containsString:@"statusbar"];
}

#pragma mark - 应用

/// 把玻璃与折射挂到容器上。签名没变时直接返回，不产生任何 CA 事务。
/// 重入保护：insertSublayer 有可能把容器的布局再触发一次，
/// 而签名是在最后才写入的 —— 没有这道闸就会自己套自己。
static BOOL gAxsIslandApplying = NO;

static void AxsIslandApply(UIView *container, AxsLiquidGlassParams params) {
    if (!container || gAxsIslandApplying) return;

    CGRect bounds = container.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (!isfinite(width) || !isfinite(height)) return;
    if (width < 60.0 || height < 20.0) return;

    // 圆角：系统会在收起/展开时改它，取不到就按药丸取半高。
    CGFloat radius = container.layer.cornerRadius;
    if (!isfinite(radius) || radius < 1.0) radius = height * 0.5;
    radius = MIN(radius, height * 0.5);

    double rim = params.rimStrength;
    double fill = params.fillAlpha;
    double specular = params.specularStrength;
    double mesh = params.meshStrength;
    NSInteger perfMode = params.perfMode;

    // 灵动岛面积小、离视线最近，玻璃感可以比别处更浓一点；但档位照配置走，
    // 省电档下 Lens 自己会把膜和高光压掉。
    double islandFill = MIN(fill * 1.15, 0.34);
    double islandBorder = MIN(rim * 1.25, 1.0);
    double islandSpecular = MIN(specular * 1.10, 1.0);
    // 省电档要跟 Lens 内部一致：它会把高光清零、膜压到 55%，签名也得跟着算，
    // 否则每次轮询都会因为"参数不同"而重建一遍图层。
    double effectiveSpecular = (perfMode <= 0) ? 0.0 : islandSpecular;
    double effectiveFill = (perfMode <= 0) ? islandFill * 0.55 : islandFill;

    AxsIslandSignature signature;
    signature.width = (float)width;
    signature.height = (float)height;
    signature.radius = (float)radius;
    signature.rim = (float)islandBorder;
    signature.fill = (float)effectiveFill;
    signature.specular = (float)effectiveSpecular;
    signature.mesh = (float)mesh;
    signature.perfMode = (int)perfMode;

    if (gAxsIslandHasSignature &&
        memcmp(&signature, &gAxsIslandSignature, sizeof(signature)) == 0) {
        return;   // 什么都没变：一个图层都不碰
    }

    gAxsIslandApplying = YES;
    // 必须 @catch 而不是 @finally：@finally 只是保证执行清理，异常照样往上抛，
    // 抛到 SpringBoard 的宿主代码里就是一次进程崩溃（= 安全模式）。
    @try {
        [AxsLiquidGlassLens axs_liquidglass_applyToView:container
                                                  radius:radius
                                                    fill:islandFill
                                                  border:islandBorder
                                                specular:islandSpecular
                                                perfMode:perfMode];

        // 折射只挂真实背景层：灵动岛内部确实有 CABackdropLayer（系统胶囊底就是它）。
        // 药丸尺寸小，网格面数很低，这一笔开销可以接受。
        if (perfMode > 0 && mesh > 0.01) {
            [AxsLiquidGlassMesh axs_liquidglass_applyRefractionToLayer:container.layer
                                                                radius:radius
                                                              strength:mesh];
        }
    } @catch (NSException *exception) {
        gAxsIslandApplying = NO;
        AxsLog(@"灵动岛：挂载异常已拦截（%@）", exception.reason);
        return;
    }
    gAxsIslandApplying = NO;

    gAxsIslandSignature = signature;
    gAxsIslandHasSignature = YES;

    if (!gAxsIslandGlassApplied) {
        gAxsIslandGlassApplied = YES;
        AxsLog(@"灵动岛：玻璃已挂载 %@（%.0fx%.0f，圆角 %.0f）",
               NSStringFromClass([container class]), width, height, radius);
    }
}

// 7.1.0 曾在这里用 MSHookMessageEx 接管容器类的 layoutSubviews，靠"尺寸一变就刷新"
// 把轮询频率压下去。7.2.0 撤掉了：那是整份代码里唯一一处**在运行时给系统类挂钩子**
// 的地方，而它对耗电的收益（一轮轮询本来就只有几次浮点比较）远小于风险 ——
// 系统类一旦被挂钩，任何一次 IMP 取值出错都是 SpringBoard 直接死。
// 现在改为"幂等 + 低频轮询"：几何签名没变时一轮扫描不会碰任何图层。
@implementation AxsLiquidGlassIslandDriver

#pragma mark - 窗口枚举

+ (NSArray<UIView *> *)axs_liquidglass_islandWindows {
    NSMutableArray<UIView *> *windows = [NSMutableArray array];

    @try {
        Class windowClass = [UIWindow class];
        SEL allSelector = NSSelectorFromString(@"_allWindowsIncludingInternalWindows:onlyVisibleWindows:");
        if ([windowClass respondsToSelector:allSelector]) {
            NSArray *(*call)(id, SEL, BOOL, BOOL) =
                (NSArray *(*)(id, SEL, BOOL, BOOL))[windowClass methodForSelector:allSelector];
            NSArray *list = call(windowClass, allSelector, YES, NO);
            if ([list isKindOfClass:[NSArray class]]) {
                for (id item in list) {
                    if ([item isKindOfClass:[UIView class]] && ![windows containsObject:item]) {
                        [windows addObject:(UIView *)item];
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        (void)exception;
    }

    @try {
        UIApplication *application = [UIApplication sharedApplication];
        if (application) {
            id list = [application valueForKey:@"windows"];
            if ([list isKindOfClass:[NSArray class]]) {
                for (id item in (NSArray *)list) {
                    if ([item isKindOfClass:[UIView class]] && ![windows containsObject:item]) {
                        [windows addObject:(UIView *)item];
                    }
                }
            }
            if (@available(iOS 15.0, *)) {
                for (UIScene *scene in application.connectedScenes) {
                    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                        if (![windows containsObject:window]) [windows addObject:window];
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        (void)exception;
    }

    // 灵动岛只可能在 SBSystemApertureWindow 里。桌面常驻窗口有十几个，
    // 每个都往下递归 5 层、几百个视图，每秒扫一遍纯属白烧 CPU 和电量。
    // 先按窗口类名筛一遍，命中就只扫这一棵子树。
    NSMutableArray<UIView *> *preferred = [NSMutableArray array];
    for (UIView *window in windows) {
        if (window.hidden || window.alpha < 0.01) continue;
        NSString *name = NSStringFromClass([window class]).lowercaseString;
        if ([name containsString:@"aperture"]) [preferred addObject:window];
    }
    if (preferred.count > 0) return preferred;

    return windows;
}

#pragma mark - 容器定位

/// 尺寸门槛：既排除整窗图层，也排除状态栏里的小圆点。
/// 灵动岛收起约 126x37，展开最大约 371x160，留一点余量到 800x260。
static BOOL AxsIslandGlassSizePlausible(UIView *view) {
    CGRect bounds = view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width < 60.0 || width > 800.0) return NO;
    if (height < 20.0 || height > 260.0) return NO;
    return YES;
}

static void AxsIslandGlassCollect(UIView *root, NSInteger depth, NSMutableArray<UIView *> *out) {
    if (!root || depth > 5 || !out) return;
    if (AxsIslandGlassIsForeignHost(NSStringFromClass([root class]))) return;

    if (AxsIslandGlassNameMatches(NSStringFromClass([root class])) &&
        AxsIslandGlassSizePlausible(root) && root.window != nil) {
        [out addObject:root];
    }
    for (UIView *child in root.subviews) {
        AxsIslandGlassCollect(child, depth + 1, out);
    }
}

+ (UIView *)axs_liquidglass_islandContainer {
    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    for (UIView *window in [self axs_liquidglass_islandWindows]) {
        AxsIslandGlassCollect(window, 0, candidates);
    }
    if (candidates.count == 0) return nil;

    // 容器是"包住药丸的最外层那个"：同样命中名字时取面积最大的一个。
    // 内层的 MagiciansCurtainView 只是黑色填充，面积更小，会被排在后面。
    UIView *best = candidates.firstObject;
    double bestArea = 0.0;
    for (UIView *candidate in candidates) {
        double area = (double)CGRectGetWidth(candidate.bounds) * (double)CGRectGetHeight(candidate.bounds);
        if (area > bestArea) {
            bestArea = area;
            best = candidate;
        }
    }
    return best;
}

#pragma mark - 刷新

+ (void)axs_liquidglass_islandTeardown {
    gAxsIslandHasSignature = NO;
    UIView *container = gAxsIslandGlassContainer;
    if (!container) return;
    [AxsLiquidGlassLens axs_liquidglass_removeFromView:container];
    [AxsLiquidGlassMesh axs_liquidglass_clearRefractionFromLayer:container.layer];
    if (gAxsIslandGlassApplied) {
        gAxsIslandGlassApplied = NO;
        AxsLog(@"灵动岛：玻璃已移除（%@）", NSStringFromClass([container class]));
    }
}

+ (void)axs_liquidglass_islandRefresh {
    AxsLiquidGlassParams params = *AxsLiquidGlassParamsGet();
    if (!params.islandGlass) {
        [self axs_liquidglass_islandTeardown];
        return;
    }

    // 最后一道保险：不管调用方是谁，闸门没开就绝不往容器里插图层。
    // 这一句让"某个新加的调用点忘了判断"这种失误变得无害。
    if (!AxsLiquidGlassGuardDecorReady()) return;

    UIView *container = [self axs_liquidglass_islandContainer];
    if (!container) {
        // 只在开关刚打开时提示一次：灵动岛还没出现（比如刚重启）不代表这套逻辑失效。
        if (!gAxsIslandGlassNoteLogged) {
            gAxsIslandGlassNoteLogged = YES;
            AxsLog(@"灵动岛：未找到 SystemAperture 容器，玻璃暂不生效");
        }
        return;
    }

    if (container != gAxsIslandGlassContainer) {
        // 容器换了（系统重建）先把旧的摘干净，避免在废弃视图上留一层玻璃。
        [self axs_liquidglass_islandTeardown];
        gAxsIslandGlassContainer = container;
    }

    AxsIslandApply(container, params);
}

+ (BOOL)axs_liquidglass_islandIsMounted {
    UIView *container = gAxsIslandGlassContainer;
    return container != nil && container.window != nil && gAxsIslandGlassApplied;
}

@end
