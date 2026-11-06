#import "AxsLiquidGlassGuard.h"
#import "AxsLiquidGlassLog.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

/// 参与判定的版本号。每次发版都要跟着 control 一起改 ——
/// 换版本 = 等级归零，等于给新包一次干净启动的机会。
static NSString * const kAxsGuardVersion = @"7.2.0";

/// 跑满这么久没出事，才算"这次启动是好的"。
static const NSInteger kAxsGuardHeartbeatSeconds = 20;
/// 上一条记录超过这么久还没心跳，就不算"刚崩过"，可能是关机放了两天。
static const NSInteger kAxsGuardStaleSeconds = 900;

static NSInteger gAxsGuardLevel = 0;
static BOOL gAxsGuardDecided = NO;
static BOOL gAxsGuardOwnsFile = NO;

static NSString *AxsGuardPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // SpringBoard 的沙箱能写 /var/mobile/Library/Caches（日志就在那儿），
        // 万一某些精简 bootstrap 没有这个目录，退化到 /tmp。
        NSArray<NSString *> *candidates = @[
            @"/var/mobile/Library/Caches/com.heli.liquid.guard",
            @"/tmp/com.heli.liquid.guard",
        ];
        for (NSString *candidate in candidates) {
            NSString *directory = [candidate stringByDeletingLastPathComponent];
            if ([[NSFileManager defaultManager] isWritableFileAtPath:directory]) {
                path = candidate;
                break;
            }
        }
        if (!path) path = candidates.lastObject;
    });
    return path;
}

typedef struct {
    int level;
    int fails;
    int ok;
    long long stamp;
    char stage[64];
} AxsGuardState;

static AxsGuardState AxsGuardRead(BOOL *versionMatches) {
    AxsGuardState state;
    memset(&state, 0, sizeof(state));
    if (versionMatches) *versionMatches = NO;

    FILE *file = fopen(AxsGuardPath().UTF8String, "r");
    if (!file) return state;

    char version[40] = {0};
    char line[256];
    while (fgets(line, sizeof(line), file)) {
        if (strncmp(line, "ver=", 4) == 0) {
            sscanf(line + 4, "%39s", version);
        } else if (strncmp(line, "level=", 6) == 0) {
            sscanf(line + 6, "%d", &state.level);
        } else if (strncmp(line, "fails=", 6) == 0) {
            sscanf(line + 6, "%d", &state.fails);
        } else if (strncmp(line, "ok=", 3) == 0) {
            sscanf(line + 3, "%d", &state.ok);
        } else if (strncmp(line, "ts=", 3) == 0) {
            sscanf(line + 3, "%lld", &state.stamp);
        } else if (strncmp(line, "stage=", 6) == 0) {
            sscanf(line + 6, "%63[^\n]", state.stage);
        }
    }
    fclose(file);

    if (versionMatches) {
        *versionMatches = (strcmp(version, kAxsGuardVersion.UTF8String) == 0);
    }
    return state;
}

static void AxsGuardWrite(int level, int fails, int ok, const char *stage) {
    if (!gAxsGuardOwnsFile) return;
    FILE *file = fopen(AxsGuardPath().UTF8String, "w");
    if (!file) return;
    fprintf(file, "ver=%s\nlevel=%d\nfails=%d\nok=%d\nts=%lld\nstage=%s\n",
            kAxsGuardVersion.UTF8String, level, fails, ok,
            (long long)time(NULL), stage ? stage : "");
    fclose(file);
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

NSInteger AxsLiquidGlassGuardBeginLaunch(void) {
    if (gAxsGuardDecided) return gAxsGuardLevel;
    gAxsGuardDecided = YES;

    if (!AxsGuardIsSpringBoard()) {
        // 其他注入进程（chronod / WidgetRenderer / 各 App）不参与判定，
        // 免得十几个进程同时读写同一个文件把计数搞乱。
        gAxsGuardLevel = 0;
        return 0;
    }
    gAxsGuardOwnsFile = YES;

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

void AxsLiquidGlassGuardNoteStage(NSString *stage) {
    if (!gAxsGuardOwnsFile || stage.length == 0) return;
    AxsGuardWrite((int)gAxsGuardLevel, 0, 0, stage.UTF8String);
}

void AxsLiquidGlassGuardScheduleHeartbeat(void) {
    if (!gAxsGuardOwnsFile) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kAxsGuardHeartbeatSeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AxsGuardWrite((int)gAxsGuardLevel, 0, 1, "steady");
        AxsLog(@"启动保护：已稳定运行 %ld 秒（等级 %ld）",
               (long)kAxsGuardHeartbeatSeconds, (long)gAxsGuardLevel);
    });
}

void AxsLiquidGlassGuardReset(void) {
    [[NSFileManager defaultManager] removeItemAtPath:AxsGuardPath() error:nil];
    gAxsGuardLevel = 0;
    gAxsGuardDecided = YES;
    AxsLog(@"启动保护：已手动解除（等级归零，下次启动按完整效果加载）");
}
