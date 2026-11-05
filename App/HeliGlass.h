#pragma once

#import <UIKit/UIKit.h>

UIColor *HeliAccent(void);
UIColor *HeliTextPrimary(void);
UIColor *HeliTextSecondary(void);
UIColor *HeliTextTertiary(void);
UIFont *HeliFont(CGFloat size, UIFontWeight weight);

/// 液态玻璃卡片：模糊底 + 圆角描边 + 顶部高光线。
@interface HeliCardView : UIView
- (instancetype)initWithTitle:(NSString *)title footer:(NSString *)footer;
- (void)addRow:(UIView *)row;
- (void)addSeparator;
@end

/// 整页背景：深空渐变 + 两团柔光。
@interface HeliBackdropView : UIView
@end
