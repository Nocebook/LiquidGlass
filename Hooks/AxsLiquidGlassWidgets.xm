#import <UIKit/UIKit.h>
#import "AxsLiquidGlassConfig.h"
#import "AxsLiquidGlassEffect.h"
#import "AxsLiquidGlassSurface.h"

// 小组件跑在 chronod / WidgetRenderer / ClockAngel 里，内存预算只有 30~50MB，
// 渲染窗口 8~10 秒。白屏的绝大多数原因是这个进程被系统杀掉，而不是脚本写错。
// 所以这里只做两件事：配置重载时同步参数，以及把可能残留的图层摘干净。
%ctor {
    @autoreleasepool {
        if (![AxsLiquidGlassSurface axs_liquidglass_isWidgetProcess]) return;
        [[AxsLiquidGlassConfig axs_liquidglass_shared] axs_liquidglass_addReloadHandler:^{
            @try {
                [AxsLiquidGlassEffect axs_liquidglass_stripDecorativeLayers];
                [AxsLiquidGlassEffect axs_liquidglass_refreshTrackedViews];
            } @catch (NSException *exception) {
                (void)exception;
            }
        }];
    }
}
