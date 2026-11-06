#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassGuard.h"
#import "AxsLiquidGlassPreferences.h"
#import "AxsLiquidGlassPrivate.h"

#import <os/lock.h>
#include <string.h>

// 7.1.0 之前的默认值是 120/1.90/0.06 —— 视觉上确实"更糊"，但 120 相当于把系统
// 原生 46 的采样核拉到 2.6 倍，滚动主屏、开合控制中心时高斯模糊要重算的面积
// 随之翻倍，这是装完插件后耗电与发热的第一来源。
// 新的默认值只抬到 88（约原生 1.9 倍）——和 120 摆在一起肉眼几乎分不出，
// GPU 侧的模糊开销却降了将近一半。想要更糊的用户自己在面板里往上拉。
static const double kAxsLiquidGlassDefaultBlurRadius = 88.0;
static const double kAxsLiquidGlassDefaultSaturation = 1.80;
static const double kAxsLiquidGlassDefaultTintAlpha = 0.28;
static const double kAxsLiquidGlassDefaultRimStrength = 0.65;
static const NSInteger kAxsLiquidGlassDefaultWidgetMode = 2;

// 液态层：这一组参数来自 88 液态玻璃（Liquidify）的观感拆解 + LiquidGlassKit 的
// 折射/菲涅尔取值。目标是"装完就看得出是液态玻璃"，而不是只把模糊调厚一点。
static const double kAxsLiquidGlassDefaultMeshStrength = 0.45;
static const double kAxsLiquidGlassDefaultFillAlpha = 0.16;
static const double kAxsLiquidGlassDefaultSpecular = 0.42;
static const NSInteger kAxsLiquidGlassDefaultPerfMode = 1;

// 旧默认值：用户没手动调过就原地升级，避免"装了新版本还是没变化"。
static const double kAxsLiquidGlassLegacyBlurRadius = 46.0;
static const double kAxsLiquidGlassLegacySaturation = 1.70;
// 7.0.0 的默认值：换成省电默认时同样只迁移"还是出厂值"的用户。
static const double kAxsLiquidGlassHeavyBlurRadius = 120.0;
static const double kAxsLiquidGlassHeavySaturation = 1.90;
static const double kAxsLiquidGlassHeavySpecular = 0.55;
static const double kAxsLiquidGlassHeavyMesh = 0.60;
static const NSInteger kAxsLiquidGlassPreferencesVersion = 3;

#pragma mark - 热路径快照

static AxsLiquidGlassParams gAxsParams;
static os_unfair_lock gAxsParamsLock = OS_UNFAIR_LOCK_INIT;

const AxsLiquidGlassParams *AxsLiquidGlassParamsGet(void) {
    // 这里必须保证"绝不重入"：早期版本用的是 dispatch_once，一旦某条路径
    // 在单例初始化过程里又反过来读快照，同一个 once 令牌被同线程二次进入就是死锁 ——
    // SpringBoard 卡在启动阶段不响应，看门狗直接杀进程，表现就是安全模式。
    // 改成一个普通的标志位：重入时直接返回当前（可能是全零的）快照，后面 reload 会补上。
    static BOOL bootstrapped = NO;
    if (!bootstrapped) {
        bootstrapped = YES;
        (void)[AxsLiquidGlassConfig axs_liquidglass_shared];
    }
    return &gAxsParams;
}

static void AxsParamsStore(const AxsLiquidGlassParams *params) {
    if (!params) return;
    os_unfair_lock_lock(&gAxsParamsLock);
    gAxsParams = *params;
    os_unfair_lock_unlock(&gAxsParamsLock);
}

// 只在升级后第一次加载时执行一次。之后用户怎么调都不再覆盖。
static void axs_liquidglass_migratePreferencesIfNeeded(void) {
    @try {
        NSDictionary *values = axs_liquidglass_readPreferences();
        NSInteger version = [values[@"prefsVersion"] isKindOfClass:[NSNumber class]]
                            ? [values[@"prefsVersion"] integerValue] : 0;
        if (version >= kAxsLiquidGlassPreferencesVersion) return;

        NSMutableDictionary *updates = [NSMutableDictionary dictionary];
        id blur = values[@"blurRadius"];
        if (![blur isKindOfClass:[NSNumber class]] ||
            fabs([blur doubleValue] - kAxsLiquidGlassLegacyBlurRadius) < 0.01 ||
            fabs([blur doubleValue] - kAxsLiquidGlassHeavyBlurRadius) < 0.01) {
            updates[@"blurRadius"] = @(kAxsLiquidGlassDefaultBlurRadius);
        }
        id saturation = values[@"saturation"];
        if (![saturation isKindOfClass:[NSNumber class]] ||
            fabs([saturation doubleValue] - kAxsLiquidGlassLegacySaturation) < 0.01 ||
            fabs([saturation doubleValue] - kAxsLiquidGlassHeavySaturation) < 0.01) {
            updates[@"saturation"] = @(kAxsLiquidGlassDefaultSaturation);
        }
        // 乳白浓度旧默认 0.06，但用户在"调了没反应"的阶段可能拉到 0。
        // 0 和 0.06 一样意味着"看不出液态"，一并升级；其它值尊重用户。
        id tint = values[@"tintAlpha"];
        if (![tint isKindOfClass:[NSNumber class]] || [tint doubleValue] <= 0.07) {
            updates[@"tintAlpha"] = @(kAxsLiquidGlassDefaultTintAlpha);
        }
        // 7.0.0 的高光 / 折射默认值偏重，跟着一起降到省电默认。
        id specular = values[@"specularStrength"];
        if (![specular isKindOfClass:[NSNumber class]] ||
            fabs([specular doubleValue] - kAxsLiquidGlassHeavySpecular) < 0.01) {
            updates[@"specularStrength"] = @(kAxsLiquidGlassDefaultSpecular);
        }
        id mesh = values[@"meshStrength"];
        if (![mesh isKindOfClass:[NSNumber class]] ||
            fabs([mesh doubleValue] - kAxsLiquidGlassHeavyMesh) < 0.01) {
            updates[@"meshStrength"] = @(kAxsLiquidGlassDefaultMeshStrength);
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

        // 低电量模式是系统级的省电信号，跟着它降档比让用户手动去面板里拨要可靠得多。
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(axs_liquidglass_powerStateChanged:)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_liquidglass_reload]; });
    }
    return self;
}

- (void)axs_liquidglass_powerStateChanged:(NSNotification *)note {
    (void)note;
    dispatch_async(self.reloadQueue, ^{ [self axs_liquidglass_reload]; });
}

/// 把当前取值压成 C 结构体，给逐帧路径用。
- (void)axs_liquidglass_rebuildParams {
    AxsLiquidGlassParams params;
    memset(&params, 0, sizeof(params));
    params.blurRadius = [self axs_liquidglass_blurRadius];
    params.saturation = [self axs_liquidglass_saturation];
    params.tintAlpha = [self axs_liquidglass_tintAlpha];
    params.rimStrength = [self axs_liquidglass_rimStrength];
    params.meshStrength = [self axs_liquidglass_meshStrength];
    params.fillAlpha = [self axs_liquidglass_fillAlpha];
    params.specularStrength = [self axs_liquidglass_specularStrength];
    params.alertsOpacity = [self axs_liquidglass_alertsOpacity];
    params.perfMode = [self axs_liquidglass_effectivePerfMode];
    params.widgetMode = [self axs_liquidglass_widgetMode];
    params.enabled = [self axs_liquidglass_isEnabled];
    params.islandGlass = [self axs_liquidglass_islandGlass];
    params.hideIsland = [self axs_liquidglass_hideIsland];
    params.lowPower = [self axs_liquidglass_isLowPower];
    params.keyboardScope = [self axs_liquidglass_scopeEnabled:@"keyboard"];
    params.appBlur = [self axs_liquidglass_appBlur];

    // 启动保护等级 1：上一次启动崩过，这次只保留"改模糊参数"这一条最安全的链路。
    // 玻璃膜、锥形描边、折射网格、灵动岛全部归零 —— 这些都要往系统图层树里
    // 插图层 / 改 mesh，是整份代码里风险最集中的部分。把参数压成 0 之后，
    // 下游每个模块都会走"清理 + 直接返回"的分支，不需要额外判断。
    if (AxsLiquidGlassGuardLevel() >= 1) {
        params.rimStrength = 0.0;
        params.fillAlpha = 0.0;
        params.specularStrength = 0.0;
        params.meshStrength = 0.0;
        params.islandGlass = NO;
        params.hideIsland = NO;
    }

    params.generation = self.generation;
    AxsParamsStore(&params);
}

- (void)axs_liquidglass_reload {
    NSDictionary *values = axs_liquidglass_readPreferences();
    self.snapshot = [values isKindOfClass:[NSDictionary class]] ? values : @{};
    self.widgetBlocklist = [self axs_liquidglass_parseBlocklist:self.snapshot[@"widgetBlocklist"]];
    self.generation = self.generation + 1;
    [self axs_liquidglass_rebuildParams];
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

- (BOOL)axs_liquidglass_lowPowerAuto {
    id value = [self axs_liquidglass_valueForKey:@"lowPowerAuto" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (BOOL)axs_liquidglass_appBlur {
    id value = [self axs_liquidglass_valueForKey:@"appBlur" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (BOOL)axs_liquidglass_isLowPower {
    if (![self axs_liquidglass_lowPowerAuto]) return NO;
    return [NSProcessInfo processInfo].isLowPowerModeEnabled;
}

- (NSInteger)axs_liquidglass_effectivePerfMode {
    NSInteger mode = [self axs_liquidglass_perfMode];
    // 低电量时直接按"省电档"渲染：不挂折射网格、去掉镜面高光、膜压淡。
    // 视觉损失有限，但省下的是整块屏幕每帧的合成开销 —— 低电量时这笔账更划算。
    if ([self axs_liquidglass_isLowPower] && mode > 0) return 0;
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
    // 隐藏灵动岛也是往系统托管视图上写 alpha/hidden，启动保护生效时一并停掉。
    if (AxsLiquidGlassGuardLevel() >= 1) return NO;
    id value = [self axs_liquidglass_valueForKey:@"hideIsland" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

// 灵动岛玻璃默认开：这一条是"看得见"的功能，装完就该有变化。
// 找不到容器时模块自己会静默退出，不会把灵动岛弄坏，所以敢默认开。
- (BOOL)axs_liquidglass_islandGlass {
    // 启动保护生效时不碰灵动岛：那块区域归系统驱动托管，动它最容易出事。
    if (AxsLiquidGlassGuardLevel() >= 1) return NO;
    id value = [self axs_liquidglass_valueForKey:@"islandGlass" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (unsigned long long)axs_liquidglass_generation {
    return _generation;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
