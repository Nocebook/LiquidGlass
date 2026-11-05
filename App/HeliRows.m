#import "HeliRows.h"
#import "HeliGlass.h"

static id HeliReadRaw(NSString *key) {
    if (key.length == 0) return nil;
    NSDictionary *values = axs_liquidglass_readPreferences();
    id value = values[key];
    return value;
}

static BOOL HeliReadBool(NSString *key, BOOL fallback) {
    id value = HeliReadRaw(key);
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static double HeliReadDouble(NSString *key, double fallback) {
    id value = HeliReadRaw(key);
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : fallback;
}

static void HeliWrite(NSString *key, id value) {
    if (key.length == 0) return;
    axs_liquidglass_writePreference(key, value, NULL);
}

#pragma mark - 基类

@implementation HeliRow

+ (NSString *)stringForValue:(id)value fallback:(NSString *)fallback {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return value;
    }
    return fallback ?: @"";
}

@end

#pragma mark - 开关

@interface HeliSwitchRow ()
@property (nonatomic, strong) UISwitch *control;
@end

@implementation HeliSwitchRow

+ (instancetype)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle
                         key:(NSString *)key defaultValue:(BOOL)defaultValue {
    HeliSwitchRow *row = [[HeliSwitchRow alloc] init];
    row.key = key;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = HeliFont(16.0, UIFontWeightMedium);
    titleLabel.textColor = HeliTextPrimary();
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *subLabel = nil;
    if (subtitle.length > 0) {
        subLabel = [[UILabel alloc] init];
        subLabel.text = subtitle;
        subLabel.font = HeliFont(12.0, UIFontWeightRegular);
        subLabel.textColor = HeliTextTertiary();
        subLabel.numberOfLines = 0;
        subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    }

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:
                              subLabel ? @[titleLabel, subLabel] : @[titleLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 2.0;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    UISwitch *control = [[UISwitch alloc] init];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    control.onTintColor = HeliAccent();
    control.on = HeliReadBool(key, defaultValue);
    [control addTarget:row action:@selector(handleSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    row.control = control;

    [row addSubview:textStack];
    [row addSubview:control];

    [NSLayoutConstraint activateConstraints:@[
        [textStack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:18.0],
        [textStack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12.0],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-18.0],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:(subtitle.length > 0 ? 68.0 : 56.0)],
        [control.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:10.0],
        [control.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-10.0],
    ]];

    return row;
}

- (void)handleSwitchChanged:(UISwitch *)sender {
    HeliWrite(self.key, @(sender.on));
    if (self.onChange) self.onChange(@(sender.on));
}

@end

#pragma mark - 滑块

@interface HeliSliderRow ()
@property (nonatomic, weak) UILabel *valueLabel;
@property (nonatomic, weak) UISlider *slider;
@property (nonatomic, assign) double minValue;
@property (nonatomic, assign) double maxValue;
@property (nonatomic, assign) NSInteger decimals;
@property (nonatomic, copy) NSString *suffix;
@property (nonatomic, assign) double pendingValue;
@end

@implementation HeliSliderRow

+ (instancetype)rowWithTitle:(NSString *)title key:(NSString *)key
                    minValue:(double)minValue maxValue:(double)maxValue
                    decimals:(NSInteger)decimals defaultValue:(double)defaultValue
                      suffix:(NSString *)suffix {
    HeliSliderRow *row = [[HeliSliderRow alloc] init];
    row.key = key;
    row.minValue = minValue;
    row.maxValue = maxValue;
    row.decimals = decimals;
    row.suffix = suffix;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    double value = HeliReadDouble(key, defaultValue);
    if (value < minValue) value = minValue;
    if (value > maxValue) value = maxValue;
    row.pendingValue = value;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = HeliFont(16.0, UIFontWeightMedium);
    titleLabel.textColor = HeliTextPrimary();
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.font = HeliFont(15.0, UIFontWeightSemibold);
    valueLabel.textColor = HeliAccent();
    valueLabel.textAlignment = NSTextAlignmentRight;
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    row.valueLabel = valueLabel;

    UISlider *slider = [[UISlider alloc] init];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = (float)minValue;
    slider.maximumValue = (float)maxValue;
    slider.value = (float)value;
    slider.minimumTrackTintColor = HeliAccent();
    slider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.16];
    [slider addTarget:row action:@selector(handleSliderChanged:) forControlEvents:UIControlEventValueChanged];
    row.slider = slider;

    [row addSubview:titleLabel];
    [row addSubview:valueLabel];
    [row addSubview:slider];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:18.0],
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor constant:12.0],
        [valueLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-18.0],
        [valueLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:8.0],
        [slider.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:18.0],
        [slider.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-18.0],
        [slider.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6.0],
        [slider.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-8.0],
        [row.heightAnchor constraintEqualToConstant:76.0],
    ]];

    [row refreshValueLabel];
    return row;
}

- (void)refreshValueLabel {
    NSString *format = [NSString stringWithFormat:@"%%.%ldf", (long)MAX(0, self.decimals)];
    NSString *text = [NSString stringWithFormat:format, self.pendingValue];
    if (self.suffix.length > 0) {
        text = [text stringByAppendingString:self.suffix];
    }
    self.valueLabel.text = text;
}

- (void)handleSliderChanged:(UISlider *)sender {
    self.pendingValue = (double)sender.value;
    [self refreshValueLabel];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(commitValue) object:nil];
    [self performSelector:@selector(commitValue) withObject:nil afterDelay:0.15];
}

- (void)commitValue {
    HeliWrite(self.key, @(self.pendingValue));
    if (self.onChange) self.onChange(@(self.pendingValue));
}

@end

#pragma mark - 分段

@interface HeliSegmentRow ()
@property (nonatomic, strong) UISegmentedControl *control;
@end

@implementation HeliSegmentRow

+ (instancetype)rowWithTitle:(NSString *)title key:(NSString *)key
                      titles:(NSArray<NSString *> *)titles
                defaultValue:(NSInteger)defaultValue {
    HeliSegmentRow *row = [[HeliSegmentRow alloc] init];
    row.key = key;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = HeliFont(16.0, UIFontWeightMedium);
    titleLabel.textColor = HeliTextPrimary();
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:titles];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    control.selectedSegmentTintColor = HeliAccent();
    if (@available(iOS 13.0, *)) {
        [control setTitleTextAttributes:@{NSForegroundColorAttributeName : [UIColor colorWithWhite:1.0 alpha:0.72]}
                               forState:UIControlStateNormal];
        [control setTitleTextAttributes:@{NSForegroundColorAttributeName : [UIColor colorWithRed:0.02 green:0.09 blue:0.16 alpha:1.0]}
                               forState:UIControlStateSelected];
    }

    double stored = HeliReadDouble(key, defaultValue);
    NSInteger index = (NSInteger)llround(stored);
    if (index < 0 || index >= (NSInteger)titles.count) index = defaultValue;
    control.selectedSegmentIndex = index;
    [control addTarget:row action:@selector(handleSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    row.control = control;

    [row addSubview:titleLabel];
    [row addSubview:control];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:18.0],
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor constant:14.0],
        [control.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:18.0],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-18.0],
        [control.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10.0],
        [control.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-14.0],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:84.0],
    ]];

    return row;
}

- (void)handleSegmentChanged:(UISegmentedControl *)sender {
    NSInteger index = (NSInteger)sender.selectedSegmentIndex;
    HeliWrite(self.key, @(index));
    if (self.onChange) self.onChange(@(index));
}

@end

#pragma mark - 文本

@interface HeliTextRow () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *field;
@end

@implementation HeliTextRow

+ (instancetype)rowWithTitle:(NSString *)title key:(NSString *)key
                placeholder:(NSString *)placeholder defaultValue:(NSString *)defaultValue {
    HeliTextRow *row = [[HeliTextRow alloc] init];
    row.key = key;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = HeliFont(16.0, UIFontWeightMedium);
    titleLabel.textColor = HeliTextPrimary();
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.text = [HeliRow stringForValue:HeliReadRaw(key) fallback:defaultValue];
    field.placeholder = placeholder;
    field.font = HeliFont(14.0, UIFontWeightRegular);
    field.textColor = HeliTextPrimary();
    field.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:placeholder ?: @""
            attributes:@{NSForegroundColorAttributeName : HeliTextTertiary()}];
    field.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
    field.layer.cornerRadius = 10.0;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.returnKeyType = UIReturnKeyDone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 10.0, 1.0)];
    field.leftViewMode = UITextFieldViewModeAlways;
    field.delegate = row;
    [field addTarget:row action:@selector(handleEditingChanged:) forControlEvents:UIControlEventEditingChanged];
    row.field = field;

    [row addSubview:titleLabel];
    [row addSubview:field];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:18.0],
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor constant:12.0],
        [field.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:18.0],
        [field.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-18.0],
        [field.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [field.heightAnchor constraintEqualToConstant:36.0],
        [field.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-12.0],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:92.0],
    ]];

    return row;
}

- (void)handleEditingChanged:(UITextField *)sender {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(commitValue) object:nil];
    [self performSelector:@selector(commitValue) withObject:nil afterDelay:0.4];
}

- (void)commitValue {
    HeliWrite(self.key, self.field.text ?: @"");
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [self commitValue];
}

@end

#pragma mark - 按钮

@interface HeliButtonRow ()
@property (nonatomic, copy) void (^actionHandler)(void);
@end

@implementation HeliButtonRow

+ (instancetype)rowWithTitle:(NSString *)title destructive:(BOOL)destructive
                      action:(void (^)(void))action {
    HeliButtonRow *row = [[HeliButtonRow alloc] init];
    row.actionHandler = action;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:destructive ? [UIColor colorWithRed:1.0 green:0.42 blue:0.42 alpha:1.0]
                                      : HeliAccent() forState:UIControlStateNormal];
    button.titleLabel.font = HeliFont(16.0, UIFontWeightSemibold);
    [button addTarget:row action:@selector(handleTap:) forControlEvents:UIControlEventTouchUpInside];

    [row addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.centerXAnchor constraintEqualToAnchor:row.centerXAnchor],
        [button.topAnchor constraintEqualToAnchor:row.topAnchor constant:10.0],
        [button.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10.0],
        [row.heightAnchor constraintEqualToConstant:54.0],
    ]];

    return row;
}

- (void)handleTap:(id)sender {
    if (self.actionHandler) self.actionHandler();
}

@end
