#pragma once

#import <UIKit/UIKit.h>

/// 灵动岛玻璃驱动。
///
/// 结构测绘（Liquidify 1.3.7 的 CCSystemApertureBackgroundDriver）给出的关键结论：
/// 灵动岛的背景不是 SBSystemApertureWindow 的子视图，而是由独立 driver 托管的
/// **容器视图**（initWithContainerView: 持有容器 + display link + settledFrames）。
/// 之前我们一直对窗口挂 setAlpha/setHidden，所以"挂钩 0 个"、效果也挂不上去。
///
/// 这里改成：先按类名在窗口树里找那个容器，再把玻璃膜与折射挂到容器上。
/// 找不到就什么都不做 —— 灵动岛是系统最敏感的区域，宁可没有效果也不能弄坏它。
@interface AxsLiquidGlassIslandDriver : NSObject

/// 窗口清单（SpringBoard 不是 UIApplication 子类，需走私有类方法取全量窗口）。
+ (NSArray<UIView *> *)axs_liquidglass_islandWindows;

/// 找到承载灵动岛的容器视图；没找到返回 nil。
+ (UIView *)axs_liquidglass_islandContainer;

/// 按当前配置刷新：开则挂玻璃，关则彻底摘掉。
+ (void)axs_liquidglass_islandRefresh;

/// 快速路径：不重新枚举窗口，只拿已跟踪的容器重算一次几何。
/// 由容器的 layoutSubviews 调用（展开/收起时逐帧），签名没变时什么都不做。
+ (void)axs_liquidglass_islandRefreshTracked;

/// 接管容器类的 layoutSubviews，让尺寸变化即时触发刷新，替代高频轮询。
/// 返回 YES 表示确实接管成功 —— 轮询可以退到很低的频率。
+ (BOOL)axs_liquidglass_islandHookLayoutForContainer:(UIView *)container;

/// 是否已经事件驱动（接管成功 = 轮询只是兜底）。
+ (BOOL)axs_liquidglass_islandIsEventDriven;

/// 摘掉玻璃（不影响"隐藏灵动岛"那条链路）。
+ (void)axs_liquidglass_islandTeardown;

@end
