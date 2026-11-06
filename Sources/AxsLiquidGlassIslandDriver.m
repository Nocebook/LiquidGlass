#import "AxsLiquidGlassIslandDriver.h"
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLens.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassMesh.h"
#import "AxsLiquidGlassPrivate.h"

static __weak UIView *gAxsIslandGlassContainer;
static BOOL gAxsIslandGlassApplied = NO;
static BOOL gAxsIslandGlassNoteLogged = NO;

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
    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    if (![config axs_liquidglass_islandGlass]) {
        [self axs_liquidglass_islandTeardown];
        return;
    }

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

    CGRect bounds = container.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width < 60.0 || height < 20.0) return;

    // 圆角：系统会在收起/展开时改它，取不到就按药丸取半高。
    CGFloat radius = container.layer.cornerRadius;
    if (radius < 1.0) radius = height * 0.5;
    radius = MIN(radius, height * 0.5);

    double rim = [config axs_liquidglass_rimStrength];
    double fill = [config axs_liquidglass_fillAlpha];
    double specular = [config axs_liquidglass_specularStrength];
    double mesh = [config axs_liquidglass_meshStrength];
    NSInteger perfMode = [config axs_liquidglass_perfMode];

    // 灵动岛面积小、离视线最近，玻璃感可以比别处更浓一点；但档位照配置走，
    // 省电档下 Lens 自己会把膜和高光压掉。
    [AxsLiquidGlassLens axs_liquidglass_applyToView:container
                                              radius:radius
                                                fill:MIN(fill * 1.15, 0.34)
                                              border:MIN(rim * 1.25, 1.0)
                                            specular:MIN(specular * 1.10, 1.0)
                                            perfMode:perfMode];

    // 折射只挂真实背景层：灵动岛内部确实有 CABackdropLayer（系统胶囊底就是它）。
    // 药丸尺寸小，网格面数很低，这一笔开销可以接受。
    if (perfMode > 0 && mesh > 0.01) {
        [AxsLiquidGlassMesh axs_liquidglass_applyRefractionToLayer:container.layer
                                                            radius:radius
                                                          strength:mesh];
    }

    if (!gAxsIslandGlassApplied) {
        gAxsIslandGlassApplied = YES;
        AxsLog(@"灵动岛：玻璃已挂载 %@（%.0fx%.0f，圆角 %.0f）",
               NSStringFromClass([container class]), width, height, radius);
    }
}

@end
