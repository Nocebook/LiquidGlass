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

/// 边缘折射强度（0~1）：给真实 CABackdropLayer 挂网格，让背景在圆角处被弯折。
- (double)axs_liquidglass_meshStrength;
/// 玻璃膜浓度（0~0.4）：整片极淡的乳白，决定"有没有玻璃本体"。
- (double)axs_liquidglass_fillAlpha;
/// 镜面高光强度（0~1）：左上角那团柔光。
- (double)axs_liquidglass_specularStrength;
/// 性能档位：0 省电（只描边+膜）、1 标准（默认，折射只给小表面）、2 极致（全尺寸折射）。
- (NSInteger)axs_liquidglass_perfMode;
/// 通知与弹窗的底色透明度（0.2~1.0）：1.0 原样，越低通知底越透。
- (double)axs_liquidglass_alertsOpacity;

/// 0 完全跳过小组件，1 只调模糊参数（默认），2 连高光层一起加。
- (NSInteger)axs_liquidglass_widgetMode;
/// 命中任一子串就跳过该小组件；只在小组件进程里生效。
- (BOOL)axs_liquidglass_isWidgetIdentifierBlocked:(NSString *)identifier;

- (BOOL)axs_liquidglass_scopeEnabled:(NSString *)scope;

/// 隐藏灵动岛：为 YES 时把灵动岛容器的 alpha 压到 0。
- (BOOL)axs_liquidglass_hideIsland;
/// 灵动岛玻璃：给 SystemAperture 容器挂玻璃膜与边缘折射（7.3.0 起默认关）。
- (BOOL)axs_liquidglass_islandGlass;
/// 描边用锥形渐变（默认关）。
/// 锥形渐变会让亮部沿圆角"扫一圈"，观感更像真玻璃，但它是 7.0.0 新写的、
/// 没在真机上验证过的形态；默认走 6.3.1 验证过的线性对角，
/// 这一项留着让用户单独试，崩了也只怪这一个开关。
- (BOOL)axs_liquidglass_conicBorder;
/// 低电量模式下是否自动降档（默认开）。
- (BOOL)axs_liquidglass_lowPowerAuto;
/// 第三方 App 里是否也加厚系统模糊（默认关）。
/// 关掉时只在 SpringBoard 内改写模糊参数 —— App 里的导航栏/键盘/侧边模糊保持系统原值，
/// 这是本插件在 App 内最大的一笔耗电来源（滚动的每一帧都要重算更大的高斯核）。
- (BOOL)axs_liquidglass_appBlur;
/// 当前是否处于"低电量生效"状态：开关打开且系统低电量模式已开启。
- (BOOL)axs_liquidglass_isLowPower;
/// 已把低电量降档算进去的档位。真正的渲染路径都读这个，而不是 perfMode。
- (NSInteger)axs_liquidglass_effectivePerfMode;
/// 每次配置重载自增，页面刷新时可据此判断是否需要重做。
- (unsigned long long)axs_liquidglass_generation;

/// 配置重载后在主线程回调，用于就地刷新已经存在的模糊视图。
- (void)axs_liquidglass_addReloadHandler:(void (^)(void))handler;

@end

/// 热路径参数快照。
///
/// 为什么需要它：`layoutSubviews` 在滚动、开合控制中心时是**逐帧**回调的，
/// 一次回调里如果连续走七八次 `-axs_liquidglass_xxx` 取值，每次都是一次
/// 消息派发 + 字典查找 + `isKindOfClass`，几十个表面叠起来就是每帧上千次查找。
/// 这些值只在配置重载 / 电量状态变化时变，所以压成一个结构体，热路径只读它。
typedef struct {
    double blurRadius;
    double saturation;
    double tintAlpha;
    double rimStrength;
    double meshStrength;
    double fillAlpha;
    double specularStrength;
    double alertsOpacity;
    NSInteger perfMode;          // 已应用低电量降档
    NSInteger widgetMode;
    BOOL enabled;
    BOOL islandGlass;
    BOOL hideIsland;
    BOOL lowPower;
    BOOL keyboardScope;
    BOOL appBlur;
    unsigned long long generation;
} AxsLiquidGlassParams;

/// 返回内部静态快照的地址。调用方必须**立刻**把需要的字段拷出来用，不要长期持有指针。
///
/// 必须 extern "C"：Hooks 里的 .xm 由 Logos 以 Objective-C++ 编译，
/// 没有这层包裹的话，这个函数在 .xm 里会被当成 C++ 符号（__Z23AxsLiquidGlassParamsGetv），
/// 而 Config.m 里是 C 符号，链接期直接 undefined。
#ifdef __cplusplus
extern "C" {
#endif
const AxsLiquidGlassParams *AxsLiquidGlassParamsGet(void);
#ifdef __cplusplus
}
#endif
