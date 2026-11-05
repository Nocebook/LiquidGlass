#pragma once

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString * const AxsLiquidGlassPreferencesDomain = @"com.axs.liquidglass";
static NSString * const AxsLiquidGlassPreferencesChanged = @"com.axs.liquidglass.preferences-changed";

// 偏好一律走 cfprefsd（CFPreferences / NSUserDefaults），不直接拼文件路径。
// roothide 的 jbroot() 会把 /var/mobile/Library/Preferences 也重定向进隐藏根，
// 那里并没有 SpringBoard 真正写入的偏好文件，直接读文件必然拿到空值。
// 走 cfprefsd 后 rootful / rootless / roothide 三种越狱的行为完全一致。
static inline NSDictionary *axs_liquidglass_readPreferences(void) {
    CFStringRef domain = (__bridge CFStringRef)AxsLiquidGlassPreferencesDomain;
    NSDictionary *values = nil;

    CFArrayRef keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        CFDictionaryRef snapshot = CFPreferencesCopyMultiple(keys, domain,
                                                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (snapshot) {
            values = (__bridge_transfer NSDictionary *)snapshot;
        }
        CFRelease(keys);
    }
    if ([values isKindOfClass:[NSDictionary class]] && values.count > 0) {
        return values;
    }

    // 兜底：部分越狱环境里 SpringBoard 与面板的 cfprefsd 缓存不同步。
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:AxsLiquidGlassPreferencesDomain];
    NSDictionary *persistent = [defaults persistentDomainForName:AxsLiquidGlassPreferencesDomain];
    return [persistent isKindOfClass:[NSDictionary class]] ? persistent : @{};
}

// 只有 PreferenceBundle 调用写入，写完整 key 后同步并广播 darwin 通知。
static inline BOOL axs_liquidglass_writePreference(NSString *key, id value, NSError **error) {
    if (key.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:AxsLiquidGlassPreferencesDomain code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Invalid preference key"}];
        }
        return NO;
    }

    CFStringRef domain = (__bridge CFStringRef)AxsLiquidGlassPreferencesDomain;
    CFStringRef cfKey = (__bridge CFStringRef)key;
    if (value) {
        CFPreferencesSetAppValue(cfKey, (__bridge CFPropertyListRef)value, domain);
    } else {
        CFPreferencesSetAppValue(cfKey, NULL, domain);
    }

    if (!CFPreferencesAppSynchronize(domain)) {
        if (error) {
            *error = [NSError errorWithDomain:AxsLiquidGlassPreferencesDomain code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"cfprefsd sync failed"}];
        }
        return NO;
    }

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)AxsLiquidGlassPreferencesChanged, NULL, NULL, true);
    return YES;
}
