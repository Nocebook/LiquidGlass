#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassPreferences.h"
#import "AxsLiquidGlassPrivate.h"

static const double kAxsLiquidGlassDefaultBlurRadius = 46.0;
static const double kAxsLiquidGlassDefaultSaturation = 1.70;
static const double kAxsLiquidGlassDefaultTintAlpha = 0.06;
static const double kAxsLiquidGlassDefaultRimStrength = 0.35;
static const NSInteger kAxsLiquidGlassDefaultWidgetMode = 1;

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
        _reloadQueue = dispatch_queue_create("com.axs.liquidglass.preferences", DISPATCH_QUEUE_SERIAL);
        _reloadHandlers = [NSMutableArray array];
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
    id value = [self axs_liquidglass_valueForKey:@"enabled" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (double)axs_liquidglass_blurRadius {
    return [self axs_liquidglass_doubleForKey:@"blurRadius" fallback:kAxsLiquidGlassDefaultBlurRadius
                                      minimum:12.0 maximum:80.0];
}

- (double)axs_liquidglass_saturation {
    return [self axs_liquidglass_doubleForKey:@"saturation" fallback:kAxsLiquidGlassDefaultSaturation
                                      minimum:1.0 maximum:2.2];
}

- (double)axs_liquidglass_tintAlpha {
    return [self axs_liquidglass_doubleForKey:@"tintAlpha" fallback:kAxsLiquidGlassDefaultTintAlpha
                                      minimum:0.0 maximum:0.20];
}

- (double)axs_liquidglass_rimStrength {
    return [self axs_liquidglass_doubleForKey:@"rimStrength" fallback:kAxsLiquidGlassDefaultRimStrength
                                      minimum:0.0 maximum:1.0];
}

- (NSInteger)axs_liquidglass_widgetMode {
    id value = [self axs_liquidglass_valueForKey:@"widgetMode" defaultValue:nil];
    NSInteger mode = [value isKindOfClass:[NSNumber class]] ? [value integerValue] : kAxsLiquidGlassDefaultWidgetMode;
    if (mode < 0 || mode > 2) mode = kAxsLiquidGlassDefaultWidgetMode;
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

- (unsigned long long)axs_liquidglass_generation {
    return _generation;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
