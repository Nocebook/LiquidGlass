#pragma once

#import <UIKit/UIKit.h>
#import "AxsLiquidGlassPreferences.h"

@interface HeliRow : UIView
@property (nonatomic, copy) NSString *key;
/// 值变化后的回调，用于刷新页面上的状态胶囊。
@property (nonatomic, copy) void (^onChange)(id value);
+ (NSString *)stringForValue:(id)value fallback:(NSString *)fallback;
@end

/// 开关行
@interface HeliSwitchRow : HeliRow
+ (instancetype)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle
                         key:(NSString *)key defaultValue:(BOOL)defaultValue;
@end

/// 滑块行
@interface HeliSliderRow : HeliRow
+ (instancetype)rowWithTitle:(NSString *)title key:(NSString *)key
                    minValue:(double)minValue maxValue:(double)maxValue
                    decimals:(NSInteger)decimals defaultValue:(double)defaultValue
                      suffix:(NSString *)suffix;
@end

/// 分段选择行
@interface HeliSegmentRow : HeliRow
+ (instancetype)rowWithTitle:(NSString *)title key:(NSString *)key
                      titles:(NSArray<NSString *> *)titles
                defaultValue:(NSInteger)defaultValue;
@end

/// 文本输入行
@interface HeliTextRow : HeliRow
+ (instancetype)rowWithTitle:(NSString *)title key:(NSString *)key
                placeholder:(NSString *)placeholder defaultValue:(NSString *)defaultValue;
@end

/// 按钮行
@interface HeliButtonRow : HeliRow
+ (instancetype)rowWithTitle:(NSString *)title destructive:(BOOL)destructive
                      action:(void (^)(void))action;
@end
