#import "AxsLiquidGlassLog.h"

#import <stdio.h>
#import <pthread.h>
#import <time.h>

// SpringBoard / chronod 这些进程沙箱被放宽，/var/mobile/Library/Caches 可写；
// 万一写不进去（某些精简 bootstrap 没有这个目录），退化到 /tmp，
// 至少还能拿到一次运行痕迹。
static NSString *AxsLogResolvedPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *candidates = @[
            @"/var/mobile/Library/Caches/com.heli.liquid.log",
            @"/tmp/com.heli.liquid.log",
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

NSString *AxsLogPath(void) {
    return AxsLogResolvedPath();
}

static pthread_mutex_t gAxsLogLock = PTHREAD_MUTEX_INITIALIZER;

void AxsLogReset(void) {
    pthread_mutex_lock(&gAxsLogLock);
    FILE *file = fopen(AxsLogResolvedPath().UTF8String, "w");
    if (file) fclose(file);
    pthread_mutex_unlock(&gAxsLogLock);
}

void AxsLog(NSString *format, ...) {
    if (format.length == 0) return;

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (!message) return;

    NSString *process = [NSProcessInfo processInfo].processName ?: @"?";

    // 不用 NSDateFormatter：它在 SpringBoard 启动阶段创建一次要几毫秒，
    // 而这段代码跑在每个注入进程的 dyld 回调里，能省就省。
    char stamp[24] = {0};
    time_t now = time(NULL);
    struct tm local;
    if (localtime_r(&now, &local)) {
        strftime(stamp, sizeof(stamp), "%H:%M:%S", &local);
    }
    NSString *line = [NSString stringWithFormat:@"%s [%@] %@\n", stamp, process, message];

    pthread_mutex_lock(&gAxsLogLock);

    NSString *path = AxsLogResolvedPath();
    // 超过 96KB 直接重写，避免长期运行把磁盘写满。
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attributes[NSFileSize] unsignedLongLongValue] > 96 * 1024) {
        FILE *truncate = fopen(path.UTF8String, "w");
        if (truncate) fclose(truncate);
    }

    FILE *file = fopen(path.UTF8String, "a");
    if (file) {
        fputs(line.UTF8String, file);
        fclose(file);
    }

    pthread_mutex_unlock(&gAxsLogLock);
}
