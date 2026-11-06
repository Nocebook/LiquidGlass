#import "AxsLiquidGlassGuard.h"
#import "AxsLiquidGlassLog.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

/// 参与判定的版本号。每次发版都要跟着 control 一起改 ——
/// 换版本 = 等级归零，等于给新包一次干净启动的机会。
static NSString * const kAxsGuardVersion = @"7.3.0";

/// 状态存放的偏好域。故意跟插件本体（com.heli.liquid）分开，
/// 免得面板的 reload 逻辑把看门狗状态当成用户配置读进去。
static NSString * const kAxsGuardDomain = @"com.heli.liquid.guard";
static NSString * const kAxsGuardStateKey = @"state";

/// 跑满这么久没出事，才算"这次启动是好的"。
static const NSInteger kAxsGuardHeartbeatSeconds = 20;
/// 上一条记录超过这么久还没心跳，就不算"刚崩过"，可能是关机放了两天。
static const NSInteger kAxsGuardStaleSeconds = 900;

static NSInteger gAxsGuardLevel = 0;
static BOOL gAxsGuardDecided = NO;
static BOOL gAxsGuardWriter = NO;
/// 装饰层闸门：启动稳定窗口结束后才会被打开。
static BOOL gAxsGuardDecorReady = NO;

typedef struct {
    int level;
    int fails;
    int ok;
    long long stamp;
    char stage[64];
} AxsGuardState;

#pragma mark - 存储

/// 这里必须走 CFPreferences，不能 fopen。
///
/// 7.2.0 就是栽在这：它直接 fopen("/var/mobile/Library/Caches/...")，
/// 而 SpringBoard 有沙盒，写失败时 fopen 返回 NULL、代码静默 return ——
/// 于是等级永远停在 0，下次启动照样全量加载，又崩，用户看到的就是
/// "怎么装都是安全模式"，而且这个死循环自己永远出不来。
/// CFPreferences 的落盘由 cfprefsd 完成（cfprefsd 以 mobile 身份写文件），
/// 沙盒进程调它不会被拒，这条通路是可靠的。
static NSString *AxsGuardReadState(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)kAxsGuardStateKey,
        (__bridge CFStringRef)kAxsGuardDomain);
    if (!value) return nil;
    NSString *result = nil;
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    }
    CFRelease(value);
    return result;
}

static void AxsGuardWriteState(NSString *state) {
    if (state.length == 0) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)kAxsGuardStateKey,
                             (__bridge CFStringRef)state,
                             (__bridge CFStringRef)kAxsGuardDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kAxsGuardDomain);
}

static AxsGuardState AxsGuardRead(BOOL *versionMatches) {
    AxsGuardState state;
    memset(&state, 0, sizeof(state));
    if (versionMatches) *versionMatches = NO;

    NSString *raw = AxsGuardReadState();
    if (raw.length == 0) return state;

    // 状态是一段 "key=value\n" 的纯文本，解析失败也只是拿不到值，不会崩。
    char buffer[512] = {0};
    const char *utf8 = raw.UTF8String;
    if (!utf8) return state;
    strncpy(buffer, utf8, sizeof(buffer) - 1);

    char version[40] = {0};
    char *cursor = buffer;
    while (cursor && *cursor) {
        char *lineEnd = strchr(cursor, '\n');
        if (lineEnd) *lineEnd = '\0';

        if (strncmp(cursor, "ver=", 4) == 0) {
            sscanf(cursor + 4, "%39s", version);
        } else if (strncmp(cursor, "level=", 6) == 0) {
            sscanf(cursor + 6, "%d", &state.level);
        } else if (strncmp(cursor, "fails=", 6) == 0) {
            sscanf(cursor + 6, "%d", &state.fails);
        } else if (strncmp(cursor, "ok=", 3) == 0) {
            sscanf(cursor + 3, "%d", &state.ok);
        } else if (strncmp(cursor, "ts=", 3) == 0) {
            sscanf(cursor + 3, "%lld", &state.stamp);
        } else if (strncmp(cursor, "stage=", 6) == 0) {
            sscanf(cursor + 6, "%63[^\n]", state.stage);
        }

        cursor = lineEnd ? lineEnd + 1 : NULL;
    }

    if (versionMatches) {
        *versionMatches = (strcmp(version, kAxsGuardVersion.UTF8String) == 0);
    }
    return state;
}

static void AxsGuardWrite(int level, int fails, int ok, const char *stage) {
    if (!gAxsGuardWriter) return;
    NSString *state = [NSString stringWithFormat:
        @"ver=%@\nlevel=%d\nfails=%d\nok=%d\nts=%lld\nstage=%s\n",
        kAxsGuardVersion, level, fails, ok, (long long)time(NULL), stage ? stage : ""];
    AxsGuardWriteState(state);
}

static BOOL AxsGuardIsSpringBoard(void) {
    static BOOL isSpringBoard;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *name = [NSProcessInfo processInfo].processName ?: @"";
        isSpringBoard = [name isEqualToString:@"SpringBoard"];
    });
    return isSpringBoard;
}

#pragma mark - 生命周期

NSInteger AxsLiquidGlassGuardBeginLaunch(void) {
    if (gAxsGuardDecided) return gAxsGuardLevel;
    gAxsGuardDecided = YES;

    if (!AxsGuardIsSpringBoard()) {
        // 其他注入进程（chronod / WidgetRenderer / 各 App）不参与判定，
        // 免得十几个进程同时读写同一份状态把计数搞乱。
        gAxsGuardLevel = 0;
        return 0;
    }
    gAxsGuardWriter = YES;

    BOOL versionMatches = NO;
    AxsGuardState state = AxsGuardRead(&versionMatches);
    long long now = (long long)time(NULL);

    if (!versionMatches) {
        // 第一次装，或者换了新版本：等级归零，重新开始数。
        gAxsGuardLevel = 0;
        AxsGuardWrite(0, 0, 0, "launch");
        AxsLog(@"启动保护：版本 %@ 首次启动，等级 0", kAxsGuardVersion);
        return 0;
    }

    // 上一次没跑出心跳 = 崩在启动阶段。时间太久远的记录不算（可能是关机放着）。
    BOOL previousCrashed = (state.ok == 0) && (now - state.stamp < kAxsGuardStaleSeconds);
    int fails = previousCrashed ? state.fails + 1 : 0;
    int level = state.level;
    if (previousCrashed && level < 2) {
        level += 1;
        AxsLog(@"启动保护：上次启动未完成（停在「%s」），降级到等级 %d",
               state.stage[0] ? state.stage : "启动阶段", level);
    } else if (previousCrashed) {
        AxsLog(@"启动保护：上次启动未完成，已经是最高降级等级 2");
    }

    gAxsGuardLevel = level;
    AxsGuardWrite(level, fails, 0, "launch");

    if (level == 0) {
        AxsLog(@"启动保护：等级 0（正常运行）");
    } else if (level == 1) {
        AxsLog(@"启动保护：等级 1 —— 只保留模糊参数，玻璃膜/描边/折射/灵动岛全部关闭。"
               @"在面板「维护 → 解除启动保护」可以恢复");
    } else {
        AxsLog(@"启动保护：等级 2 —— 本次启动不加载任何 Hook。"
               @"在面板「维护 → 解除启动保护」可以恢复");
    }
    return level;
}

NSInteger AxsLiquidGlassGuardLevel(void) {
    return gAxsGuardLevel;
}

BOOL AxsLiquidGlassGuardDecorReady(void) {
    // 还没做启动判定时一律不动手：宁可这一瞬间少个效果，也不要在
    // 不确定等级的情况下往系统图层树里插东西。
    if (!gAxsGuardDecided) return NO;
    if (gAxsGuardLevel != 0) return NO;
    if (gAxsGuardDecorReady) return YES;
    // 非 SpringBoard 进程不参与启动判定，也就不受稳定窗口约束：
    // 小组件进程的渲染窗口只有 8~10 秒，等 12 秒等于永远不生效。
    // 它们的崩溃不会诱发安全模式，代价只是那个小组件变空白。
    return !AxsGuardIsSpringBoard();
}

void AxsLiquidGlassGuardMarkDecorReady(void) {
    if (gAxsGuardDecorReady) return;
    gAxsGuardDecorReady = YES;
    AxsLog(@"启动保护：稳定窗口结束，装饰层放开（等级 %ld）", (long)gAxsGuardLevel);
}

void AxsLiquidGlassGuardNoteStage(NSString *stage) {
    if (!gAxsGuardWriter || stage.length == 0) return;
    AxsGuardWrite((int)gAxsGuardLevel, 0, 0, stage.UTF8String);
}

void AxsLiquidGlassGuardScheduleHeartbeat(void) {
    if (!gAxsGuardWriter) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kAxsGuardHeartbeatSeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AxsGuardWrite((int)gAxsGuardLevel, 0, 1, "steady");
        AxsLog(@"启动保护：已稳定运行 %ld 秒（等级 %ld）",
               (long)kAxsGuardHeartbeatSeconds, (long)gAxsGuardLevel);
    });
}

void AxsLiquidGlassGuardReset(void) {
    CFPreferencesSetAppValue((__bridge CFStringRef)kAxsGuardStateKey,
                             NULL,
                             (__bridge CFStringRef)kAxsGuardDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kAxsGuardDomain);
    gAxsGuardLevel = 0;
    gAxsGuardDecided = YES;
    gAxsGuardDecorReady = YES;
    AxsLog(@"启动保护：已手动解除（等级归零，下次启动按完整效果加载）");
}

NSString *AxsLiquidGlassGuardStatusText(void) {
    BOOL versionMatches = NO;
    AxsGuardState state = AxsGuardRead(&versionMatches);
    if (!versionMatches) return nil;

    NSString *levelText = state.level <= 0 ? @"完整效果"
                        : (state.level == 1 ? @"仅模糊" : @"已停用");
    return [NSString stringWithFormat:@"上次启动：%s · 保护等级 %d（%@）",
            state.ok ? "稳定" : "未完成", state.level, levelText];
}
