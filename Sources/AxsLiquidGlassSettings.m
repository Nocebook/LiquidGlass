#import "AxsLiquidGlassSettings.h"

#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

#import <substrate.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>

static void (*axs_liquidglass_origSetBlurRadius)(id, SEL, double);
static void (*axs_liquidglass_origSetSaturation)(id, SEL, double);
static void (*axs_liquidglass_origSetTintAlpha)(id, SEL, double);
static void (*axs_liquidglass_origSetColorTint)(id, SEL, id);
static void (*axs_liquidglass_origApplySettings)(id, SEL, id);

static BOOL gAxsSettingsInstalled = NO;

// 每个 settings 对象只做一次"整体改写"，避免 applySettings 反复调用导致
// 模糊半径被一轮轮乘上去（46 → 120 → 260 → …）。
static char kAxsSettingsTouchedKey;

// 记录日志用：前若干个不同 settings 类的实测数值，数量够了就停，避免刷爆日志。
static NSMutableSet<NSString *> *gAxsLoggedClasses;

/// 当前进程是不是系统界面（SpringBoard 本身）。
/// _UIBackdropViewSettings 的 setter 是**全进程**生效的：插件一旦注入，
/// App 里的导航栏、键盘、侧边栏、弹出菜单的模糊半径也会被抬到配置值，
/// 滚动时每帧重算更大的高斯核 —— 这是待机耗电之外最明显的一项。
/// 所以默认只在系统界面里改写，App 内恢复原生观感。
///
/// 这里刻意**不用 dispatch_once**：这个判定在 setter 热路径里，而 once 令牌
/// 被同线程重入就是死锁，卡在 SpringBoard 主线程上等于一次崩溃（7.2.0 踩过）。
/// 普通静态标志即使被多线程同时首次赋值，写进去的也是同一个结果，无害。
static BOOL AxsSettingsInSystemUI(void) {
    static int cached = -1;
    if (cached < 0) {
        cached = [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"] ? 1 : 0;
    }
    return cached == 1;
}

static BOOL AxsSettingsActive(void) {
    if (![[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_isEnabled]) return NO;
    if (AxsSettingsInSystemUI()) return YES;
    // App 内是否加厚由面板「第三方 App 也加厚模糊」决定，默认关。
    return [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_appBlur];
}

/// 系统给自己的玻璃表面填的原始半径：控制中心 / Dock / 文件夹 实测是 46。
/// 直接填 46 等于没改，所以把"比配置值小的表面"统一抬到配置值。
///
/// 这个函数必须幂等：setter 会被反复调用，早期版本写成 max(配置, 原值 × 2.2)，
/// 同一块表面第二轮就 46 → 120 → 264，半径一轮轮乘上去，GPU 直接被打满
/// —— 日志里那句 "blur: 120.0 -> 220.0" 就是这么来的。
/// 现在只做"抬到下限"，再调多少次结果都一样；上限 176 保住画质与耗电的平衡。
/// 小于 8 的一律放行：那是系统本来就不打算模糊的表面（分隔线、纯色底）。
static double AxsTargetBlur(double original) {
    if (original < 8.0) return original;
    double configured = [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_blurRadius];
    if (configured < 8.0) return original;
    double target = configured > original ? configured : original;
    return target > 176.0 ? 176.0 : target;
}

static void AxsLogOnceForClass(id settings, double before, double after) {    if (!settings) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gAxsLoggedClasses = [NSMutableSet set];
    });
    NSString *name = NSStringFromClass([settings class]);
    @synchronized (gAxsLoggedClasses) {
        if (gAxsLoggedClasses.count >= 8 || [gAxsLoggedClasses containsObject:name]) return;
        [gAxsLoggedClasses addObject:name];
    }
    AxsLog(@"settings %@ blur: %.1f -> %.1f", name, before, after);
}

/// 锁屏上滑、通知中心下拉、控制中心收起这些动画里，系统会**逐帧**重设模糊半径
/// （模糊随手势进度插值）。如果我们每一帧都把它抬到上限，就等于每帧跑一次
/// 全屏 176pt 的高斯模糊 —— GPU 直接打满，画面冻住，表现就是"上滑滑不动"。
///
/// 判据：同一个 settings 对象在 50ms 内被再次设置，就认为它正处在动画里，原样放行。
/// 动画结束后第一次设置（间隔 > 50ms）仍然照常抬升，静态观感不受影响。
static __unsafe_unretained id gAxsLastBlurTarget;
static CFAbsoluteTime gAxsLastBlurStamp = 0.0;

static BOOL AxsBlurIsAnimating(id settings) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL animating = (settings == gAxsLastBlurTarget) &&
                     ((now - gAxsLastBlurStamp) < 0.05);
    gAxsLastBlurTarget = settings;
    gAxsLastBlurStamp = now;
    return animating;
}

static void AxsHookSetBlurRadius(id self, SEL _cmd, double radius) {
    double value = radius;
    if (AxsSettingsActive() && !AxsBlurIsAnimating(self)) {
        value = AxsTargetBlur(radius);
        if (value != radius) AxsLogOnceForClass(self, radius, value);
    }
    if (axs_liquidglass_origSetBlurRadius) {
        axs_liquidglass_origSetBlurRadius(self, _cmd, value);
    }
}

static void AxsHookSetSaturation(id self, SEL _cmd, double factor) {
    double value = factor;
    if (factor > 0.0 && AxsSettingsActive()) {
        // 只提高不降低：有些表面本来就带 0 以外的饱和度，压低会让颜色发灰。
        double wanted = [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_saturation];
        value = factor > wanted ? factor : wanted;
    }
    if (axs_liquidglass_origSetSaturation) {
        axs_liquidglass_origSetSaturation(self, _cmd, value);
    }
}

static void AxsHookSetTintAlpha(id self, SEL _cmd, double alpha) {
    double value = alpha;
    if (alpha > 0.0 && AxsSettingsActive()) {
        double wanted = [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_tintAlpha];
        value = alpha > wanted ? alpha : wanted;
    }
    if (axs_liquidglass_origSetTintAlpha) {
        axs_liquidglass_origSetTintAlpha(self, _cmd, value);
    }
}

static void AxsHookSetColorTint(id self, SEL _cmd, id color) {
    id value = color;
    if (color && AxsSettingsActive()) {
        // 统一成纯白：系统自带的是偏蓝的灰，染出来像"脏玻璃"，白色才是乳浊质感。
        value = [UIColor whiteColor];
    }
    if (axs_liquidglass_origSetColorTint) {
        axs_liquidglass_origSetColorTint(self, _cmd, value);
    }
}

// 兜底：有些路径不经过 setter，而是整份 settings 直接交给 _UIBackdropView。
static void AxsModifySettingsObject(id settings) {
    if (!settings || !AxsSettingsActive()) return;
    if (objc_getAssociatedObject(settings, &kAxsSettingsTouchedKey)) return;
    objc_setAssociatedObject(settings, &kAxsSettingsTouchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    @try {
        double before = [[settings valueForKey:@"blurRadius"] doubleValue];
        double after = AxsTargetBlur(before);
        if (after != before) {
            [settings setValue:@(after) forKey:@"blurRadius"];
            AxsLogOnceForClass(settings, before, after);
        }
        [settings setValue:@([config axs_liquidglass_saturation]) forKey:@"saturationDeltaFactor"];
        [settings setValue:@([config axs_liquidglass_tintAlpha]) forKey:@"colorTintAlpha"];
        [settings setValue:[UIColor whiteColor] forKey:@"colorTint"];
    } @catch (NSException *exception) {
        (void)exception;
    }
}

static void AxsHookApplySettings(id self, SEL _cmd, id settings) {
    if (AxsSettingsActive()) {
        AxsModifySettingsObject(settings);
    }
    if (axs_liquidglass_origApplySettings) {
        axs_liquidglass_origApplySettings(self, _cmd, settings);
    }
}

@implementation AxsLiquidGlassSettings

+ (BOOL)axs_liquidglass_isInstalled {
    return gAxsSettingsInstalled;
}

+ (BOOL)axs_liquidglass_installHooksIfAvailable {
    if (gAxsSettingsInstalled) return YES;

    Class settingsClass = NSClassFromString(@"_UIBackdropViewSettings");
    if (!settingsClass) {
        AxsLog(@"settings: _UIBackdropViewSettings 不存在，退回 UIVisualEffectView 路径");
        return NO;
    }

    NSInteger hooked = 0;

    // 只在"类自己实现"时挂：setBlurRadius: 若挂在 _UISettings 父类上，
    // MSHookMessageEx 会改掉整个设置体系，波及所有 _UISettings 子类。
    if (axs_liquidglass_classImplements(settingsClass, @selector(setBlurRadius:))) {
        MSHookMessageEx(settingsClass, @selector(setBlurRadius:),
                        (IMP)AxsHookSetBlurRadius,
                        (IMP *)&axs_liquidglass_origSetBlurRadius);
        hooked += 1;
    }
    if (axs_liquidglass_classImplements(settingsClass, @selector(setSaturationDeltaFactor:))) {
        MSHookMessageEx(settingsClass, @selector(setSaturationDeltaFactor:),
                        (IMP)AxsHookSetSaturation,
                        (IMP *)&axs_liquidglass_origSetSaturation);
        hooked += 1;
    }
    if (axs_liquidglass_classImplements(settingsClass, @selector(setColorTintAlpha:))) {
        MSHookMessageEx(settingsClass, @selector(setColorTintAlpha:),
                        (IMP)AxsHookSetTintAlpha,
                        (IMP *)&axs_liquidglass_origSetTintAlpha);
        hooked += 1;
    }
    if (axs_liquidglass_classImplements(settingsClass, @selector(setColorTint:))) {
        MSHookMessageEx(settingsClass, @selector(setColorTint:),
                        (IMP)AxsHookSetColorTint,
                        (IMP *)&axs_liquidglass_origSetColorTint);
        hooked += 1;
    }

    gAxsSettingsInstalled = (hooked > 0);

    // 兜底第二条：整份 settings 交给 _UIBackdropView 的路径。
    Class backdropClass = NSClassFromString(@"_UIBackdropView");
    if (backdropClass && axs_liquidglass_classImplements(backdropClass, @selector(applySettings:))) {
        MSHookMessageEx(backdropClass, @selector(applySettings:),
                        (IMP)AxsHookApplySettings,
                        (IMP *)&axs_liquidglass_origApplySettings);
        hooked += 1;
        gAxsSettingsInstalled = YES;
    }

    AxsLog(@"_UIBackdropViewSettings 挂载 %ld 个入口（installed=%d）", (long)hooked, gAxsSettingsInstalled);
    return gAxsSettingsInstalled;
}

@end
