#pragma once

#import <Foundation/Foundation.h>

/// 面板写入、Tweak 只读的配置快照。所有默认值只在缺键时生效，从不写回磁盘。
@interface AxsLiquidGlassConfig : NSObject

+ (instancetype)axs_liquidglass_shared;
- (BOOL)axs_liquidglass_isEnabled;
- (id)axs_liquidglass_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)axs_liquidglass_reload;

- (double)axs_liquidglass_blurRadius;
- (double)axs_liquidglass_saturation;
- (double)axs_liquidglass_tintAlpha;
- (double)axs_liquidglass_rimStrength;

/// 0 完全跳过小组件，1 只调模糊参数（默认），2 连高光层一起加。
- (NSInteger)axs_liquidglass_widgetMode;
/// 命中任一子串就跳过该小组件；只在小组件进程里生效。
- (BOOL)axs_liquidglass_isWidgetIdentifierBlocked:(NSString *)identifier;

- (BOOL)axs_liquidglass_scopeEnabled:(NSString *)scope;

/// 隐藏灵动岛：为 YES 时把灵动岛容器的 alpha 压到 0。
- (BOOL)axs_liquidglass_hideIsland;
/// 每次配置重载自增，页面刷新时可据此判断是否需要重做。
- (unsigned long long)axs_liquidglass_generation;

/// 配置重载后在主线程回调，用于就地刷新已经存在的模糊视图。
- (void)axs_liquidglass_addReloadHandler:(void (^)(void))handler;

@end
