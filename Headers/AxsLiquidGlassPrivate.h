#pragma once

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

// UIKit 的 _UICustomBlurEffect 是公开 UIBlurEffect 的私有子类，
// 它是唯一能单独改半径/饱和度/染色而不必重建视图层级的入口。
// 这里不声明它的接口：类符号走 NSClassFromString，属性走
// respondsToSelector + KVC 双重兜底，取不到时降级到系统材质而不是崩。
static inline id AxsLiquidGlassBlurEffectClass(void) {
    return NSClassFromString(@"_UICustomBlurEffect");
}

static inline BOOL AxsLiquidGlassSetNumber(id target, NSString *selectorName, NSString *key, double value) {
    if (!target || selectorName.length == 0) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    if ([target respondsToSelector:selector]) {
        IMP imp = [target methodForSelector:selector];
        void (*call)(id, SEL, double) = (void (*)(id, SEL, double))imp;
        call(target, selector, value);
        return YES;
    }
    @try {
        [target setValue:@(value) forKey:key];
        return YES;
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
}

static inline BOOL AxsLiquidGlassSetObject(id target, NSString *selectorName, NSString *key, id value) {
    if (!target || selectorName.length == 0) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    if ([target respondsToSelector:selector]) {
        IMP imp = [target methodForSelector:selector];
        void (*call)(id, SEL, id) = (void (*)(id, SEL, id))imp;
        call(target, selector, value);
        return YES;
    }
    @try {
        [target setValue:value forKey:key];
        return YES;
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
}

static inline double AxsLiquidGlassClamp(double value, double minimum, double maximum) {
    if (!isfinite(value)) return minimum;
    return fmax(minimum, fmin(maximum, value));
}

// 只判断"这个类自己有没有实现"，不查父类：
// 对继承来的方法挂钩子会把影响扩散到父类的所有子类。
static inline BOOL axs_liquidglass_classImplements(Class cls, SEL selector) {
    if (!cls || !selector) return NO;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int index = 0; index < count; index++) {
        if (method_getName(methods[index]) == selector) {
            found = YES;
            break;
        }
    }
    if (methods) free(methods);
    return found;
}
