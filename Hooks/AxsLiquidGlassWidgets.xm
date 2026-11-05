#import <UIKit/UIKit.h>
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassEffect.h"
#import "AxsLiquidGlassSurface.h"

// 小组件跑在 chronod / WidgetRenderer / ClockAngel 里，渲染结果会被归档成快照。
// 往这些视图上叠自绘图层，最常见的后果是快照失败——桌面直接空一块（家人地图那类地图组件尤其明显）。
// 所以这些进程只允许改模糊参数，配置重载时再把可能残留的图层摘干净。
%ctor {
    @autoreleasepool {
        if (![AxsLiquidGlassSurface axs_liquidglass_isWidgetProcess]) return;
        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            [AxsLiquidGlassEffect axs_liquidglass_stripDecorativeLayers];
        }];
    }
}
