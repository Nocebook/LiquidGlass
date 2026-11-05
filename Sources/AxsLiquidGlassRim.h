#pragma once

#import <UIKit/UIKit.h>

/// 给一块模糊视图加"玻璃厚度"：左上斜向高光 + 一圈边缘折射线。
/// 只用 CALayer，不接管触摸；同一视图重复调用只更新数值，不叠加图层。
@interface AxsLiquidGlassRim : NSObject

+ (void)axs_liquidglass_installOnView:(UIView *)view strength:(double)strength;
+ (void)axs_liquidglass_removeFromView:(UIView *)view;
+ (void)axs_liquidglass_layoutInView:(UIView *)view;
+ (BOOL)axs_liquidglass_hasRim:(UIView *)view;

@end
