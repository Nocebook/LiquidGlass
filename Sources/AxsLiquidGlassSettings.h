#pragma once

#import <Foundation/Foundation.h>

/// iOS 15/16 的系统毛玻璃（控制中心、Dock、文件夹、通知、键盘…）
/// 绝大多数不是 UIVisualEffectView，而是 _UIBackdropView + _UIBackdropViewSettings。
/// 参数只存在于 settings 对象上（blurRadius / saturationDeltaFactor / colorTintAlpha），
/// 在 _UIBackdropView 上找 setBlurRadius: 永远找不到，这也是之前"完全没效果"的根因。
///
/// 这里直接挂 settings 的 setter：只要系统自己设过一次模糊参数，就会被替换成
/// 用户配置的值。系统原本 radius 为 0 的表面（不需要模糊的地方）原样放行，
/// 不会凭空给不该模糊的区域加模糊。
@interface AxsLiquidGlassSettings : NSObject

+ (BOOL)axs_liquidglass_installHooksIfAvailable;
+ (BOOL)axs_liquidglass_isInstalled;

@end
