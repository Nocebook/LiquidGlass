#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassPreferences.h"
#import "AxsLiquidGlassPrivate.h"

// 6.1.0-21 的默认值是 46/1.70/0.06 —— 实测系统自己的 _UIBackdropViewSettings
// 默认 blurRadius 就是 46，等于我们把它设成了原值，视觉上零变化。
// 新的默认值必须拉开差距：模糊翻倍、乳白明显、饱和度更高。
static const double kAxsLiquidGlassDefaultBlurRadius = 120.0;
static const double kAxsLiquidGlassDefaultSaturation = 1.90;
static const double kAxsLiquidGlassDefaultTintAlpha = 0.28;
static const double kAxsLiquidGlassDefaultRimStrength = 0.65;
static const NSInteger kAxsLiquidGlassDefaultWidgetMode = 2;

// 液态层：这一组参数来自 88 液态玻璃（Liquidify）的观感拆解 + LiquidGlassKit 的
// 折射/菲涅尔取值。目标是"装完就看得出是液态玻璃"，而不是只把模糊调厚一点。
static const double kAxsLiquidGlassDefaultMeshStrength = 0.60;
static const double kAxsLiquidGlassDefaultFillAlpha = 0.16;
static const double kAxsLiquidGlassDefaultSpecular = 0.55;
static const NSInteger kAxsLiquidGlassDefaultPerfMode = 1;

// 旧默认值：用户没手动调过就原地升级，避免"装了新版本还是没变化"。
static const double kAxsLiquidGlassLegacyBlurRadius = 46.0;
static const double kAxsLiquidGlassLegacySaturation = 1.70;
static const NSInteger kAxsLiquidGlassPreferencesVersion = 2;

// 只在升级后第一次加载时执行一次。之后用户怎么调都不再覆盖。
static void axs_liquidglass_migratePreferencesIfNeeded(void) {
    @try {
        NSDictionary *values = axs_liquidglass_readPreferences();
        NSInteger version = [values[@"prefsVersion"] isKindOfClass:[NSNumber class]]
                            ? [values[@"prefsVersion"] integerValue] : 0;
        if (version >= kAxsLiquidGlassPreferencesVersion) return;

        NSMutableDictionary *updates = [NSMutableDictionary dictionary];
        id blur = values[@"blurRadius"];
        if (![blur isKindOfClass:[NSNumber class]] || fabs([blur doubleValue] - kAxsLiquidGlassLegacyBlurRadius) < 0.01) {
            updates[@"blurRadius"] = @(kAxsLiquidGlassDefaultBlurRadius);
        }
        id saturation = values[@"saturation"];
        if (![saturation isKindOfClass:[NSNumber class]] ||
            fabs([saturation doubleValue] - kAxsLiquidGlassLegacySaturation) < 0.01) {
            updates[@"saturation"] = @(kAxsLiquidGlassDefaultSaturation);
        }
        // 乳白浓度旧默认 0.06，但用户在"调了没反应"的阶段可能拉到 0。
        // 0 和 0.06 一样意味着"看不出液态"，一并升级；其它值尊重用户。
        id tint = values[@"tintAlpha"];
        if (![tint isKindOfClass:[NSNumber class]] || [tint doubleValue] <= 0.07) {
            updates[@"tintAlpha"] = @(kAxsLiquidGlassDefaultTintAlpha);
        }
        updates[@"prefsVersion"] = @(kAxsLiquidGlassPreferencesVersion);

        CFStringRef domain = (__bridge CFStringRef)AxsLiquidGlassPreferencesDomain;
        for (NSString *key in updates) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                     (__bridge CFPropertyListRef)updates[key], domain);
        }
        CFPreferencesAppSynchronize(domain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge CFStringRef)AxsLiquidGlassPreferencesChanged, NULL, NULL, true);
    } @catch (NSException *exception) {
        (void)exception;
    }
}

@interface AxsLiquidGlassConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, copy) NSArray<NSString *> *widgetBlocklist;
@property (atomic, assign) unsigned long long generation;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@property (nonatomic, strong) NSMutableArray<void (^)(void)> *reloadHandlers;
- (double)axs_liquidglass_doubleForKey:(NSString *)key fallback:(double)fallback
                               minimum:(double)minimum maximum:(double)maximum;
- (NSArray<NSString *> *)axs_liquidglass_parseBlocklist:(id)raw;
@end

static void axs_liquidglass_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    AxsLiquidGlassConfig *config = (__bridge AxsLiquidGlassConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config axs_liquidglass_reload];
    });
}

@implementation AxsLiquidGlassConfig

+ (instancetype)axs_liquidglass_shared {
    static AxsLiquidGlassConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.heli.liquid.preferences", DISPATCH_QUEUE_SERIAL);
        _reloadHandlers = [NSMutableArray array];
        // 先做一次旧默认值迁移，再读快照，否则这一轮还是读到 46/0.06。
        axs_liquidglass_migratePreferencesIfNeeded();
        [self axs_liquidglass_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, axs_liquidglass_preferencesDidChange,
            (__bridge CFStringRef)AxsLiquidGlassPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_liquidglass_reload]; });
    }
    return self;
}

- (void)axs_liquidglass_reload {
    NSDictionary *values = axs_liquidglass_readPreferences();
    self.snapshot = [values isKindOfClass:[NSDictionary class]] ? values : @{};
    self.widgetBlocklist = [self axs_liquidglass_parseBlocklist:self.snapshot[@"widgetBlocklist"]];
    self.generation = self.generation + 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<void (^)(void)> *handlers;
        @synchronized (self.reloadHandlers) {
            handlers = [self.reloadHandlers copy];
        }
        for (id item in handlers) {
            void (^handler)(void) = item;
            handler();
        }
    });
}

- (void)axs_liquidglass_addReloadHandler:(void (^)(void))handler {
    if (!handler) return;
    @synchronized (self.reloadHandlers) {
        [self.reloadHandlers addObject:[handler copy]];
    }
}

- (id)axs_liquidglass_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    if (key.length == 0) return defaultValue;
    NSDictionary *snapshot = self.snapshot;
    id value = snapshot[key];
    return value ?: defaultValue;
}

- (double)axs_liquidglass_doubleForKey:(NSString *)key fallback:(double)fallback
                       minimum:(double)minimum maximum:(double)maximum {
    id value = [self axs_liquidglass_valueForKey:key defaultValue:nil];
    double number = [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : fallback;
    return AxsLiquidGlassClamp(number, minimum, maximum);
}

- (BOOL)axs_liquidglass_isEnabled {
    // 装完就要能看到效果：缺键时按开启处理，用户主动关掉才写 false。
    id value = [self axs_liquidglass_valueForKey:@"enabled" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (BOOL)axs_liquidglass_appBlur {
    // 默认关：只在 SpringBoard 里改写模糊。打开后连 App 内部的导航栏、键盘、
    // 侧边栏也会被加厚，滚动时每帧重算更大的高斯核 —— 用户主动打开才付这笔钱。
    id value = [self axs_liquidglass_valueForKey:@"appBlur" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (double)axs_liquidglass_blurRadius {
    return [self axs_liquidglass_doubleForKey:@"blurRadius" fallback:kAxsLiquidGlassDefaultBlurRadius
                                      minimum:40.0 maximum:200.0];
}

- (double)axs_liquidglass_saturation {
    return [self axs_liquidglass_doubleForKey:@"saturation" fallback:kAxsLiquidGlassDefaultSaturation
                                      minimum:1.0 maximum:2.50];
}

- (double)axs_liquidglass_tintAlpha {
    return [self axs_liquidglass_doubleForKey:@"tintAlpha" fallback:kAxsLiquidGlassDefaultTintAlpha
                                      minimum:0.0 maximum:0.60];
}

- (double)axs_liquidglass_alertsOpacity {
    return [self axs_liquidglass_doubleForKey:@"alertsOpacity" fallback:1.0
                                      minimum:0.2 maximum:1.0];
}

- (double)axs_liquidglass_rimStrength {
    return [self axs_liquidglass_doubleForKey:@"rimStrength" fallback:kAxsLiquidGlassDefaultRimStrength
                                      minimum:0.0 maximum:1.0];
}

- (double)axs_liquidglass_meshStrength {
    return [self axs_liquidglass_doubleForKey:@"meshStrength" fallback:kAxsLiquidGlassDefaultMeshStrength
                                      minimum:0.0 maximum:1.0];
}

- (double)axs_liquidglass_fillAlpha {
    return [self axs_liquidglass_doubleForKey:@"fillAlpha" fallback:kAxsLiquidGlassDefaultFillAlpha
                                      minimum:0.0 maximum:0.40];
}

- (double)axs_liquidglass_specularStrength {
    return [self axs_liquidglass_doubleForKey:@"specularStrength" fallback:kAxsLiquidGlassDefaultSpecular
                                      minimum:0.0 maximum:1.0];
}

- (NSInteger)axs_liquidglass_perfMode {
    id value = [self axs_liquidglass_valueForKey:@"perfMode" defaultValue:nil];
    NSInteger mode = [value isKindOfClass:[NSNumber class]] ? [value integerValue] : kAxsLiquidGlassDefaultPerfMode;
    if (mode < 0 || mode > 2) mode = kAxsLiquidGlassDefaultPerfMode;
    return mode;
}

- (NSInteger)axs_liquidglass_widgetMode {
    id value = [self axs_liquidglass_valueForKey:@"widgetMode" defaultValue:nil];
    NSInteger mode = [value isKindOfClass:[NSNumber class]] ? [value integerValue] : kAxsLiquidGlassDefaultWidgetMode;
    if (mode < 0 || mode > 3) mode = kAxsLiquidGlassDefaultWidgetMode;
    return mode;
}

- (NSArray<NSString *> *)axs_liquidglass_parseBlocklist:(id)raw {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    if ([raw isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)raw) {
            if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
                [tokens addObject:[item lowercaseString]];
            }
        }
        return tokens;
    }
    if (![raw isKindOfClass:[NSString class]]) return tokens;
    // 面板里是逗号分隔的文本框，这里统一成小写子串表。
    for (NSString *piece in [(NSString *)raw componentsSeparatedByString:@","]) {
        NSString *token = [[piece stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        if (token.length > 0) [tokens addObject:token];
    }
    return tokens;
}

- (BOOL)axs_liquidglass_isWidgetIdentifierBlocked:(NSString *)identifier {
    if (identifier.length == 0) return NO;
    NSString *lowercase = [identifier lowercaseString];
    for (NSString *token in self.widgetBlocklist) {
        if ([lowercase containsString:token]) return YES;
    }
    return NO;
}

- (BOOL)axs_liquidglass_scopeEnabled:(NSString *)scope {
    if (scope.length == 0) return NO;
    NSString *key = [@"scope" stringByAppendingString:
                     [scope stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                         withString:[[scope substringToIndex:1] uppercaseString]]];
    id value = [self axs_liquidglass_valueForKey:key defaultValue:nil];
    if (![value isKindOfClass:[NSNumber class]]) return YES;  // 缺键时按开启处理
    return [value boolValue];
}

- (BOOL)axs_liquidglass_hideIsland {
    id value = [self axs_liquidglass_valueForKey:@"hideIsland" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

#pragma mark - 液态角标

- (BOOL)axs_liquidglass_badgeEnabled {
    id value = [self axs_liquidglass_valueForKey:@"badgeGlass" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (double)axs_liquidglass_badgeBackgroundAlpha {
    return [self axs_liquidglass_doubleForKey:@"badgeBackgroundAlpha" fallback:0.10
                                      minimum:0.0 maximum:1.0];
}

- (BOOL)axs_liquidglass_badgeKeepColor {
    id value = [self axs_liquidglass_valueForKey:@"badgeKeepColor" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (BOOL)axs_liquidglass_badgeBreathing {
    id value = [self axs_liquidglass_valueForKey:@"badgeBreathing" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (BOOL)axs_liquidglass_badgeBlur {
    id value = [self axs_liquidglass_valueForKey:@"badgeBlur" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (unsigned long long)axs_liquidglass_generation {
    return _generation;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
