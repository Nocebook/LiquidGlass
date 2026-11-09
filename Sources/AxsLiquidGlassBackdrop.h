#pragma once

#import <UIKit/UIKit.h>

/// 桌面 Dock / 文件夹这类表面在 iOS 16 走的是私有 _UIBackdropView，
/// 不经过 UIVisualEffectView，所以单独补一条只调参数、不叠加图层的处理路径。
/// 任何一个私有 setter 探测不到就直接放弃，绝不破坏原有层级。
@interface AxsLiquidGlassBackdrop : NSObject

+ (void)axs_liquidglass_installHooksIfAvailable;
+ (void)axs_liquidglass_applyIfNeeded:(UIView *)view;
+ (void)axs_liquidglass_refreshTrackedViews;

@end
