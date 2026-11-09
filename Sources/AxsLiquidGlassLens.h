#pragma once

#import <UIKit/UIKit.h>

/// 玻璃膜：在模糊层之上叠一组**静态**图层，模拟真实玻璃的四层光学结构。
///
///   1. fill      整片极淡的乳白，上亮下暗（玻璃本体）
///   2. specular  左上角一团镜面高光（光源）
///   3. border    定向渐变描边：左上亮、右下暗（厚度感）
///   4. shadow    底边一条极淡内阴影（离面感）
///
/// 全部是 CALayer 静态属性，没有定时器、没有逐帧回调、不读屏幕内容，
/// 布局变化时才重排一次，耗电跟"多贴了一张图"同级。
@interface AxsLiquidGlassLens : NSObject

+ (void)axs_liquidglass_applyToView:(UIView *)view
                             radius:(CGFloat)radius
                               fill:(double)fill
                             border:(double)border
                           specular:(double)specular
                           perfMode:(NSInteger)perfMode;

+ (void)axs_liquidglass_layoutView:(UIView *)view radius:(CGFloat)radius;
+ (void)axs_liquidglass_removeFromView:(UIView *)view;
+ (BOOL)axs_liquidglass_hasLens:(UIView *)view;

@end
