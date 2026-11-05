#import "AxsLiquidGlassSettings.h"

#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassLog.h"
#import "AxsLiquidGlassPrivate.h"

#import <substrate.h>
#import <objc/runtime.h>

static void (*axs_liquidglass_origSetBlurRadius)(id, SEL, double);
static void (*axs_liquidglass_origSetSaturation)(id, SEL, double);
static void (*axs_liquidglass_origSetTintAlpha)(id, SEL, double);
static void (*axs_liquidglass_origSetColorTint)(id, SEL, id);
static void (*axs_liquidglass_origApplySettings)(id, SEL, id);

static BOOL gAxsSettingsInstalled = NO;
static BOOL gAxsLoggedFirstApply = NO;

static BOOL AxsSettingsActive(void) {
    return [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_isEnabled];
}

static void AxsHookSetBlurRadius(id self, SEL _cmd, double radius) {
    double value = radius;
    // 系统原本不模糊的表面（radius≈0）原样放行，避免给不该模糊的区域硬加模糊。
    if (radius > 0.5 && AxsSettingsActive()) {
        value = [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_blurRadius];
        if (!gAxsLoggedFirstApply) {
            gAxsLoggedFirstApply = YES;
            AxsLog(@"settings apply blur: %.1f -> %.1f", radius, value);
        }
    }
    if (axs_liquidglass_origSetBlurRadius) {
        axs_liquidglass_origSetBlurRadius(self, _cmd, value);
    }
}

static void AxsHookSetSaturation(id self, SEL _cmd, double factor) {
    double value = factor;
    if (factor > 0.0 && AxsSettingsActive()) {
        value = [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_saturation];
    }
    if (axs_liquidglass_origSetSaturation) {
        axs_liquidglass_origSetSaturation(self, _cmd, value);
    }
}

static void AxsHookSetTintAlpha(id self, SEL _cmd, double alpha) {
    double value = alpha;
    if (alpha > 0.0 && AxsSettingsActive()) {
        double wanted = [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_tintAlpha];
        value = fmax(alpha, wanted);
    }
    if (axs_liquidglass_origSetTintAlpha) {
        axs_liquidglass_origSetTintAlpha(self, _cmd, value);
    }
}

static void AxsHookSetColorTint(id self, SEL _cmd, id color) {
    id value = color;
    if (color && AxsSettingsActive()) {
        value = [UIColor whiteColor];
    }
    if (axs_liquidglass_origSetColorTint) {
        axs_liquidglass_origSetColorTint(self, _cmd, value);
    }
}

// 兜底：有些路径不经过 setter，而是整份 settings 直接交给 _UIBackdropView。
// 在应用前把参数改掉，效果和 setter 路径一致。
static void AxsModifySettingsObject(id settings) {
    if (!settings || !AxsSettingsActive()) return;
    AxsLiquidGlassConfig *config = [AxsLiquidGlassConfig axs_liquidglass_shared];
    @try {
        [settings setValue:@([config axs_liquidglass_blurRadius]) forKey:@"blurRadius"];
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
