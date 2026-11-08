#import "GSPRootListController.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <notify.h>

#define GS_DOMAIN @"com.heli.liquid"
#define GS_RELOAD "com.heli.liquid/reload"
#define GS_DUMP   "com.heli.liquid/dump"

@implementation GSPRootListController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Glassify";
    }
    return self;
}

#pragma mark - 控件工厂

- (PSSpecifier *)switchCell:(NSString *)label key:(NSString *)key defaultValue:(BOOL)def {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:label
                                                     target:self
                                                        set:@selector(setPref:specifier:)
                                                        get:@selector(readPref:)
                                                     detail:nil
                                                       cell:PSSwitchCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:@(def) forKey:@"default"];
    return sp;
}

- (PSSpecifier *)sliderCell:(NSString *)label
                        key:(NSString *)key
                        min:(double)min
                        max:(double)max
                 defaultVal:(double)def {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:label
                                                     target:self
                                                        set:@selector(setPref:specifier:)
                                                        get:@selector(readPref:)
                                                     detail:nil
                                                       cell:PSSliderCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:@(def) forKey:@"default"];
    [sp setProperty:@(min) forKey:@"min"];
    [sp setProperty:@(max) forKey:@"max"];
    [sp setProperty:@(YES) forKey:@"showValue"];
    return sp;
}

- (PSSpecifier *)groupCell:(NSString *)name footer:(NSString *)footer {
    // 不用 groupSpecifierWithName:，不同版本 Preferences 头文件不保证声明它；
    // 走通用构造 + label 属性最稳。
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:nil
                                                        set:nil
                                                        get:nil
                                                     detail:nil
                                                       cell:PSGroupCell
                                                       edit:nil];
    if (footer.length) [sp setProperty:footer forKey:@"footerText"];
    return sp;
}

- (PSSpecifier *)buttonCell:(NSString *)label action:(SEL)action {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:label
                                                     target:self
                                                        set:nil
                                                        get:nil
                                                     detail:nil
                                                       cell:PSButtonCell
                                                       edit:nil];
    [sp setProperty:[NSNumber numberWithInt:1] forKey:@"enabled"];

    // PSSpecifier 的 action 在不同 SDK 头文件里声明不一致，走 runtime 最稳
    SEL setAction = @selector(setAction:);
    if ([sp respondsToSelector:setAction]) {
        ((void (*)(id, SEL, SEL))objc_msgSend)(sp, setAction, action);
    }

    return sp;
}

#pragma mark - 数据

- (id)readPref:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPreferencesAppSynchronize((__bridge CFStringRef)GS_DOMAIN);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)GS_DOMAIN);
    if (value) return (__bridge_transfer id)value;
    return [specifier propertyForKey:@"default"];
}

- (void)setPref:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFTypeRef)value,
                             (__bridge CFStringRef)GS_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)GS_DOMAIN);
    notify_post(GS_RELOAD);
}

#pragma mark - 界面

- (id)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *specs = [NSMutableArray array];

    [specs addObject:[self groupCell:@"排查开关"
                              footer:@"默认全部打开。如果又进安全模式，先关掉这里的总开关再注销，就能确认是不是挂钩引起；然后逐个打开定位。"]];
    [specs addObject:[self switchCell:@"启用挂钩总开关" key:@"HooksEnabled" defaultValue:YES]];
    [specs addObject:[self switchCell:@"挂钩 A：didMoveToWindow" key:@"HookMove" defaultValue:YES]];
    [specs addObject:[self switchCell:@"挂钩 B：layoutSubviews" key:@"HookLayout" defaultValue:NO]];

    [specs addObject:[self groupCell:@"总开关"
                              footer:@"以下参数只在挂钩打开后生效。"]];
    [specs addObject:[self switchCell:@"启用 Glassify" key:@"Enabled" defaultValue:YES]];

    [specs addObject:[self groupCell:@"通知角标"
                              footer:@"角标底板会被调淡，玻璃层透出壁纸。想要纯透明玻璃就把「保留角标颜色」关掉。"]];
    [specs addObject:[self switchCell:@"角标玻璃" key:@"Badge" defaultValue:YES]];
    [specs addObject:[self sliderCell:@"原底板不透明度"
                                  key:@"BadgeBackgroundAlpha"
                                  min:0.0
                                  max:1.0
                          defaultVal:0.15]];
    [specs addObject:[self switchCell:@"保留角标颜色" key:@"BadgeKeepColor" defaultValue:YES]];
    [specs addObject:[self switchCell:@"未读呼吸动画" key:@"BadgeBreathing" defaultValue:YES]];

    [specs addObject:[self groupCell:@"调试"
                              footer:@"打开后点「立即导出一次」，用 Console 或 idevicesyslog 查看 [Glassify] 开头的行。"]];
    [specs addObject:[self switchCell:@"调试：允许导出" key:@"DebugTree" defaultValue:NO]];
    [specs addObject:[self buttonCell:@"立即导出一次" action:@selector(dumpTree:)]];

    _specifiers = specs;
    return _specifiers;
}

- (void)dumpTree:(PSSpecifier *)specifier {
    notify_post(GS_DUMP);
}

@end
