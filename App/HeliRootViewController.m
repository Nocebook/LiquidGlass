#import "HeliRootViewController.h"
#import "HeliGlass.h"
#import "HeliRows.h"

#import <spawn.h>

extern char **environ;

static BOOL HeliReadBoolValue(NSString *key, BOOL fallback) {
    id value = axs_liquidglass_readPreferences()[key];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static BOOL HeliSpawn(NSString *path, NSArray<NSString *> *arguments) {
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

static BOOL HeliRespring(void) {
    NSArray<NSString *> *killalls = @[@"/var/jb/usr/bin/killall", @"/usr/bin/killall"];
    for (NSString *path in killalls) {
        if (HeliSpawn(path, @[@"-9", @"SpringBoard"])) return YES;
    }
    NSArray<NSString *> *reloaders = @[@"/var/jb/usr/bin/sbreload", @"/usr/bin/sbreload"];
    for (NSString *path in reloaders) {
        if (HeliSpawn(path, @[])) return YES;
    }
    return NO;
}

static NSArray<NSString *> *HeliAllKeys(void) {
    return @[@"enabled", @"blurRadius", @"saturation", @"tintAlpha", @"rimStrength",
             @"scopeHome", @"scopeControlCenter", @"scopeAlerts", @"scopeKeyboard",
             @"hideIsland", @"widgetMode", @"widgetBlocklist"];
}

@interface HeliRootViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIView *pill;
@property (nonatomic, strong) UILabel *pillLabel;
@property (nonatomic, strong) UILabel *statusLine;
@end

@implementation HeliRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    HeliBackdropView *backdrop = [[HeliBackdropView alloc] initWithFrame:self.view.bounds];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:backdrop];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAlways;
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    [self rebuildContent];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - 构建

- (void)rebuildContent {
    if (self.contentStack) {
        [self.contentStack removeFromSuperview];
        self.contentStack = nil;
    }

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    [self.scrollView addSubview:stack];
    self.contentStack = stack;

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:28.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-40.0],
        [stack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-16.0],
    ]];

    [stack addArrangedSubview:[self buildHero]];
    [stack addArrangedSubview:[self buildMasterCard]];
    [stack addArrangedSubview:[self buildLookCard]];
    [stack addArrangedSubview:[self buildScopeCard]];
    [stack addArrangedSubview:[self buildIslandCard]];
    [stack addArrangedSubview:[self buildWidgetCard]];
    [stack addArrangedSubview:[self buildActionCard]];
    [stack addArrangedSubview:[self buildFootnote]];

    [stack setCustomSpacing:26.0 afterView:stack.arrangedSubviews.firstObject];
    [self refreshStatus];
}

- (UIView *)buildHero {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.text = @"liquid";
    title.font = HeliFont(38.0, UIFontWeightBold);
    title.textColor = HeliTextPrimary();
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *badge = [[UILabel alloc] init];
    badge.text = @"HL";
    badge.font = HeliFont(12.0, UIFontWeightHeavy);
    badge.textColor = [UIColor colorWithRed:0.02 green:0.09 blue:0.16 alpha:1.0];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.backgroundColor = HeliAccent();
    badge.layer.cornerRadius = 7.0;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    badge.clipsToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"液态玻璃主题 · iOS 16 隐根适配";
    subtitle.font = HeliFont(13.0, UIFontWeightMedium);
    subtitle.textColor = HeliTextSecondary();
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *pill = [[UIView alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.layer.cornerRadius = 12.0;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    pill.layer.borderWidth = 1.0;
    pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;

    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.layer.cornerRadius = 3.5;
    dot.tag = 901;
    [pill addSubview:dot];

    UILabel *pillLabel = [[UILabel alloc] init];
    pillLabel.font = HeliFont(12.0, UIFontWeightSemibold);
    pillLabel.textColor = HeliTextSecondary();
    pillLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [pill addSubview:pillLabel];
    self.pillLabel = pillLabel;
    self.pill = pill;

    self.statusLine = subtitle;

    [container addSubview:title];
    [container addSubview:badge];
    [container addSubview:subtitle];
    [container addSubview:pill];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4.0],
        [title.topAnchor constraintEqualToAnchor:container.topAnchor],
        [badge.leadingAnchor constraintEqualToAnchor:title.trailingAnchor constant:8.0],
        [badge.centerYAnchor constraintEqualToAnchor:title.centerYAnchor constant:-2.0],
        [badge.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor],
        [badge.widthAnchor constraintEqualToConstant:30.0],
        [badge.heightAnchor constraintEqualToConstant:19.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2.0],

        [pill.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [pill.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:12.0],
        [pill.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [pill.heightAnchor constraintEqualToConstant:26.0],
        [pill.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor],

        [dot.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10.0],
        [dot.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [dot.widthAnchor constraintEqualToConstant:7.0],
        [dot.heightAnchor constraintEqualToConstant:7.0],
        [pillLabel.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:6.0],
        [pillLabel.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [pillLabel.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-11.0],
    ]];

    return container;
}

- (UIView *)buildMasterCard {
    __weak typeof(self) weakSelf = self;
    HeliCardView *card = [[HeliCardView alloc] initWithTitle:@"总开关" footer:@"改完即时生效，不需要注销。"];
    HeliSwitchRow *row = [HeliSwitchRow rowWithTitle:@"启用液态玻璃"
                                            subtitle:@"关闭后立刻回到系统原生模糊"
                                                 key:@"enabled"
                                        defaultValue:YES];
    row.onChange = ^(id value) { [weakSelf refreshStatus]; };
    [card addRow:row];
    return card;
}

- (UIView *)buildLookCard {
    HeliCardView *card = [[HeliCardView alloc] initWithTitle:@"玻璃质感"
                                                      footer:@"半径越大越像厚磨砂；饱和度决定底色透不透；乳白浓度是玻璃里的那层白雾。"];

    [card addRow:[HeliSliderRow rowWithTitle:@"模糊半径" key:@"blurRadius"
                                   minValue:12.0 maxValue:80.0 decimals:0
                               defaultValue:46.0 suffix:@""]];
    [card addSeparator];
    [card addRow:[HeliSliderRow rowWithTitle:@"色彩饱和度" key:@"saturation"
                                   minValue:1.0 maxValue:2.2 decimals:2
                               defaultValue:1.70 suffix:@""]];
    [card addSeparator];
    [card addRow:[HeliSliderRow rowWithTitle:@"乳白浓度" key:@"tintAlpha"
                                   minValue:0.0 maxValue:0.20 decimals:3
                               defaultValue:0.060 suffix:@""]];
    [card addSeparator];
    [card addRow:[HeliSliderRow rowWithTitle:@"边缘高光" key:@"rimStrength"
                                   minValue:0.0 maxValue:1.0 decimals:2
                               defaultValue:0.35 suffix:@""]];
    return card;
}

- (UIView *)buildScopeCard {
    HeliCardView *card = [[HeliCardView alloc] initWithTitle:@"作用范围"
                                                      footer:@"键盘默认关闭：高光会压住候选字，看不清。"];

    [card addRow:[HeliSwitchRow rowWithTitle:@"主屏 / Dock / 文件夹"
                                    subtitle:nil key:@"scopeHome" defaultValue:YES]];
    [card addSeparator];
    [card addRow:[HeliSwitchRow rowWithTitle:@"控制中心"
                                    subtitle:nil key:@"scopeControlCenter" defaultValue:YES]];
    [card addSeparator];
    [card addRow:[HeliSwitchRow rowWithTitle:@"通知与弹窗"
                                    subtitle:nil key:@"scopeAlerts" defaultValue:YES]];
    [card addSeparator];
    [card addRow:[HeliSwitchRow rowWithTitle:@"键盘"
                                    subtitle:nil key:@"scopeKeyboard" defaultValue:NO]];
    return card;
}

- (UIView *)buildIslandCard {
    HeliCardView *card = [[HeliCardView alloc] initWithTitle:@"灵动岛"
        footer:@"开启后灵动岛整块透明，来电、音乐、计时器的胶囊动画也不再显示。适合截图或想要干净顶栏的时候。"];

    [card addRow:[HeliSwitchRow rowWithTitle:@"隐藏灵动岛"
                                    subtitle:@"关掉立刻恢复原样"
                                         key:@"hideIsland" defaultValue:NO]];
    return card;
}

- (UIView *)buildWidgetCard {
    HeliCardView *card = [[HeliCardView alloc] initWithTitle:@"小组件"
        footer:@"小组件进程内存只有 30~50MB、渲染窗口 8~10 秒，超限会被系统直接杀掉，表现就是白板。默认「边缘折光」不加任何图层，只改模糊和描边，最稳。地图类组件出问题就填进跳过列表。"];

    [card addRow:[HeliSegmentRow rowWithTitle:@"处理强度" key:@"widgetMode"
                                       titles:@[@"跳过", @"仅参数", @"折光", @"完整"]
                                 defaultValue:2]];
    [card addSeparator];
    [card addRow:[HeliTextRow rowWithTitle:@"跳过列表" key:@"widgetBlocklist"
                              placeholder:@"逗号分隔，匹配包名子串"
                             defaultValue:@"autonavi,amap"]];
    return card;
}

- (UIView *)buildActionCard {
    HeliCardView *card = [[HeliCardView alloc] initWithTitle:@"维护" footer:nil];

    __weak typeof(self) weakSelf = self;
    [card addRow:[HeliButtonRow rowWithTitle:@"重启桌面（效果异常时用）" destructive:NO action:^{
        if (!HeliRespring()) {
            [weakSelf presentMessage:@"找不到 killall / sbreload" detail:@"请用 Filza 或前端工具手动注销。"];
        }
    }]];
    [card addSeparator];
    [card addRow:[HeliButtonRow rowWithTitle:@"恢复默认设置" destructive:YES action:^{
        [weakSelf confirmReset];
    }]];
    return card;
}

- (UIView *)buildFootnote {
    UILabel *label = [[UILabel alloc] init];
    label.text = @"所有设置即时写入，改一下就能看到变化。\n装完没反应的话，先在总开关确认是开启状态。";
    label.font = HeliFont(11.0, UIFontWeightRegular);
    label.textColor = HeliTextTertiary();
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

#pragma mark - 状态

- (void)refreshStatus {
    BOOL enabled = HeliReadBoolValue(@"enabled", YES);
    UIView *dot = [self.pill viewWithTag:901];
    dot.backgroundColor = enabled ? [UIColor colorWithRed:0.32 green:0.92 blue:0.62 alpha:1.0]
                                  : [UIColor colorWithWhite:1.0 alpha:0.30];
    self.pillLabel.text = enabled ? @"已启用" : @"已停用";
    self.pillLabel.textColor = enabled ? HeliTextPrimary() : HeliTextSecondary();
    self.pill.backgroundColor = enabled ? [UIColor colorWithRed:0.32 green:0.92 blue:0.62 alpha:0.14]
                                       : [UIColor colorWithWhite:1.0 alpha:0.08];
    self.pill.layer.borderColor = enabled
        ? [UIColor colorWithRed:0.32 green:0.92 blue:0.62 alpha:0.35].CGColor
        : [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
}

#pragma mark - 动作

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认"
        message:@"会清空全部自定义数值，回到初始效果。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        for (NSString *key in HeliAllKeys()) {
            axs_liquidglass_writePreference(key, nil, NULL);
        }
        [weakSelf rebuildContent];
        [weakSelf presentMessage:@"已恢复默认" detail:@"数值已清空，当前按内置默认效果渲染。"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentMessage:(NSString *)title detail:(NSString *)detail {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
