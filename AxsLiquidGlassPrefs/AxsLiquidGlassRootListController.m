#import "AxsLiquidGlassRootListController.h"
#import "AxsLiquidGlassPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import "AxsLiquidGlassSliderCell.h"

extern char **environ;

static NSString * const kAxsLiquidGlassRepositoryURL = @"https://nocebook.github.io/heli/";

static BOOL AxsLiquidGlassSpawn(NSString *path, NSArray<NSString *> *arguments) {
    if (path.length == 0) return NO;
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) return NO;

    NSMutableArray<NSString *> *all = [NSMutableArray arrayWithObject:path];
    [all addObjectsFromArray:arguments ?: @[]];

    NSUInteger count = all.count;
    char **argv = calloc(count + 1, sizeof(char *));
    if (!argv) return NO;
    for (NSUInteger index = 0; index < count; index++) {
        argv[index] = strdup(all[index].UTF8String);
    }
    argv[count] = NULL;

    pid_t pid = 0;
    int result = posix_spawn(&pid, path.UTF8String, NULL, NULL, argv, environ);
    for (NSUInteger index = 0; index < count; index++) {
        free(argv[index]);
    }
    free(argv);
    return result == 0;
}

static BOOL AxsLiquidGlassRespring(void) {
    for (NSString *path in @[@"/var/jb/usr/bin/killall", @"/usr/bin/killall"]) {
        if (AxsLiquidGlassSpawn(path, @[@"-9", @"SpringBoard"])) return YES;
    }
    for (NSString *path in @[@"/var/jb/usr/bin/sbreload", @"/usr/bin/sbreload"]) {
        if (AxsLiquidGlassSpawn(path, @[])) return YES;
    }
    return NO;
}

@interface AxsLiquidGlassRootListController () <AxsLiquidGlassSliderCellHandler>
@end

@implementation AxsLiquidGlassRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"AxsLiquidGlassRoot"
                                                           target:self] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"维护" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_liquidglass_addButton:@"重启桌面（效果异常时用）"
                                 action:@selector(axs_liquidglass_respring:)
                                     to:items];

        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"关于" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_liquidglass_addButton:@"打开 Heli 越狱源"
                                 action:@selector(axs_liquidglass_openRepository:)
                                     to:items];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)axs_liquidglass_addButton:(NSString *)title action:(SEL)action to:(NSMutableArray *)items {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:title target:self
                          set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    item.buttonAction = action;
    [items addObject:item];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return axs_liquidglass_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!axs_liquidglass_writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查 cfprefsd 写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}

- (void)axs_liquidglass_openURL:(NSURL *)url fallback:(NSURL *)fallback {
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        if (fallback) {
            [self axs_liquidglass_openURL:fallback fallback:nil];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开链接"
                message:@"请确认已安装 Sileo。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)axs_liquidglass_openRepository:(id)sender {
    // Sileo 要求整条 URL 作为路径段编码，包括它自己的冒号斜杠。
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [kAxsLiquidGlassRepositoryURL stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    NSURL *primary = [NSURL URLWithString:[@"sileo://source/" stringByAppendingString:encoded]];
    [self axs_liquidglass_openURL:primary fallback:[NSURL URLWithString:kAxsLiquidGlassRepositoryURL]];
}

- (void)axs_liquidglass_respring:(id)sender {
    if (AxsLiquidGlassRespring()) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法重启桌面"
        message:@"找不到 killall / sbreload，请用 Filza 或快捷指令手动注销。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([PSListController instancesRespondToSelector:_cmd]) {
        [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    }
    if ([cell isKindOfClass:[AxsLiquidGlassSliderCell class]]) {
        AxsLiquidGlassSliderCell *sliderCell = (AxsLiquidGlassSliderCell *)cell;
        sliderCell.handler = self;
        [sliderCell axs_liquidglass_reloadState];
    }
}

- (double)axs_liquidglass_sliderValueForSpecifier:(PSSpecifier *)specifier {
    id value = [self readPreferenceValue:specifier];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0.0;
}

- (void)axs_liquidglass_setSliderValue:(double)value specifier:(PSSpecifier *)specifier {
    double minimum = [[specifier propertyForKey:@"min"] doubleValue];
    double maximum = [[specifier propertyForKey:@"max"] doubleValue];
    if (!isfinite(minimum)) minimum = 0.0;
    if (!isfinite(maximum) || maximum <= minimum) maximum = minimum + 1.0;
    if (!isfinite(value)) value = minimum;
    [self setPreferenceValue:@(fmax(minimum, fmin(maximum, value))) specifier:specifier];
}

@end
