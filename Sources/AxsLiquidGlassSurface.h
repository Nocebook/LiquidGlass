#pragma once

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, AxsLiquidGlassSurfaceKind) {
    AxsLiquidGlassSurfaceKindNone = 0,
    AxsLiquidGlassSurfaceKindHome,          // 主屏图标层
    AxsLiquidGlassSurfaceKindDock,
    AxsLiquidGlassSurfaceKindFolder,
    AxsLiquidGlassSurfaceKindSearchPill,    // 主屏搜索胶囊
    AxsLiquidGlassSurfaceKindAppLibrary,    // 资源库
    AxsLiquidGlassSurfaceKindControlCenter, // 控制中心模块
    AxsLiquidGlassSurfaceKindAlert,         // 通知、弹窗、上下文菜单、锁屏播放器
    AxsLiquidGlassSurfaceKindContextMenu,   // 长按弹出的上下文菜单
    AxsLiquidGlassSurfaceKindKeyboard,
    AxsLiquidGlassSurfaceKindWidget,
    /// 锁屏。它的模糊是被"上滑进度"逐帧驱动的：改它的半径等于把解锁动画按死在每一帧上，
    /// 所以这一类表面一律不碰，连模糊参数都不改。
    AxsLiquidGlassSurfaceKindLockScreen,
};

/// 判断一个模糊视图属于哪类表面，以及当前配置下该不该动它。
/// 分类结果按视图缓存；只走 superview 链，不读文件、不访问单例以外的状态。
@interface AxsLiquidGlassSurface : NSObject

+ (AxsLiquidGlassSurfaceKind)axs_liquidglass_kindForView:(UIView *)view;
+ (BOOL)axs_liquidglass_isWidgetProcess;
+ (BOOL)axs_liquidglass_shouldHandleView:(UIView *)view kind:(AxsLiquidGlassSurfaceKind)kind;
+ (BOOL)axs_liquidglass_allowsDecorativeLayersForKind:(AxsLiquidGlassSurfaceKind)kind;

@end
