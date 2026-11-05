#pragma once

#import <UIKit/UIKit.h>

/// 把系统的 UIBlurEffect 换成一个参数化的私有模糊效果，并按配置决定要不要加高光层。
/// 同一视图只处理一次；配置变化时通过注册表就地重刷，不必注销。
@interface AxsLiquidGlassEffect : NSObject

+ (void)axs_liquidglass_applyToEffectView:(UIVisualEffectView *)view;
+ (void)axs_liquidglass_handleEffectChange:(UIVisualEffectView *)view;
+ (void)axs_liquidglass_handleHierarchyChange:(UIVisualEffectView *)view;
+ (void)axs_liquidglass_layoutTrackedView:(UIView *)view;
+ (void)axs_liquidglass_refreshTrackedViews;
+ (void)axs_liquidglass_stripDecorativeLayers;
+ (BOOL)axs_liquidglass_isTrackedView:(UIView *)view;
+ (BOOL)axs_liquidglass_isApplyingToView:(UIView *)view;

@end
