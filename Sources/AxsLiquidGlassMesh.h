#pragma once

#import <UIKit/UIKit.h>

/// 边缘折射：给视图内部真实的 CABackdropLayer 挂一张 CAMeshTransform，
/// 让玻璃在靠近圆角处像透镜一样把背后的内容弯折一点。
///
/// 这是 88 液态玻璃（Liquidify）和 iOS 26 原生液态玻璃的观感来源：
/// 不是叠一层白色描边，而是"透过玻璃看到的背景在边缘被压弯"。
/// 参数全部来自配置，网格按（尺寸,圆角,强度）缓存，同一形状只生成一次。
@interface AxsLiquidGlassMesh : NSObject

/// 找到 view 内部真实的 CABackdropLayer 并挂上折射网格。
/// 找不到（系统改了层级 / 该表面本身没有 backdrop）就静默跳过，不叠替代图层。
+ (BOOL)axs_liquidglass_applyRefractionToView:(UIView *)view
                                       radius:(CGFloat)radius
                                     strength:(double)strength
                                     perfMode:(NSInteger)perfMode;

/// 直接对指定图层挂网格。
/// 灵动岛这类表面没有 UIVisualEffectView，只有裸露的 CABackdropLayer，
/// 走视图入口一路查找反而找不到，所以单独留一个图层入口。
+ (BOOL)axs_liquidglass_applyRefractionToLayer:(CALayer *)layer
                                        radius:(CGFloat)radius
                                      strength:(double)strength;

/// 从视图子树里捞出第一个 CABackdropLayer（给别的模块复用，避免各自写递归）。
+ (CALayer *)axs_liquidglass_backdropLayerInView:(UIView *)view;

/// 摘掉图层级网格（配合 applyRefractionToLayer: 使用）。
+ (void)axs_liquidglass_clearRefractionFromLayer:(CALayer *)layer;

/// 摘掉网格，恢复系统原样。
+ (void)axs_liquidglass_clearRefractionFromView:(UIView *)view;

/// 判断是否已经挂过（用于日志与去重）。
+ (BOOL)axs_liquidglass_hasRefraction:(UIView *)view;

@end
