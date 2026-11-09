#pragma once

#import <UIKit/UIKit.h>

/// 液态角标：把桌面图标右下角那枚通知角标换成一块小玻璃。
///
/// 系统的角标是 `SBIconBadgeView`，由一整块纯红底板 + 一个白色计数组成。
/// 纯色底板上叠任何半透明层都看不出"玻璃"，所以流程必须是：
///   1. 采样并记住底板颜色与其透明度
///   2. 把底板压到很淡（默认 0.10），自己再按采样色补一层很淡的染色
///   3. 在最底层插一层「模糊 + 上亮下暗的乳白 + 定向描边」的玻璃
///   4. 计数文字保持原样压在最上面
///
/// 全部挂载动作都在 didMoveToWindow 之后的 runloop 里做，layoutSubviews 里
/// 只重新断言属性（不插视图、不改层级）—— 8.0.0 就是因为在布局回调里
/// insertSubview 触发递归布局，直接被看门狗杀进程。
@interface AxsLiquidGlassBadge : NSObject

/// 只在 SpringBoard 里有效：找不到 SBIconBadgeView 就返回 NO，不装任何钩子。
+ (BOOL)axs_liquidglass_installHooksIfAvailable;
+ (BOOL)axs_liquidglass_isInstalled;

/// 配置变更后按新参数就地重刷（不需要注销）。
+ (void)axs_liquidglass_refreshAll;

@end
