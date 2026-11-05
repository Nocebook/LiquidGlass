#import "HeliGlass.h"

UIColor *HeliAccent(void) {
    return [UIColor colorWithRed:0.40 green:0.80 blue:1.00 alpha:1.0];
}

UIColor *HeliTextPrimary(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.96];
}

UIColor *HeliTextSecondary(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.62];
}

UIColor *HeliTextTertiary(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.38];
}

UIFont *HeliFont(CGFloat size, UIFontWeight weight) {
    UIFont *font = [UIFont systemFontOfSize:size weight:weight];
    if (@available(iOS 13.0, *)) {
        UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (descriptor) {
            UIFont *rounded = [UIFont fontWithDescriptor:descriptor size:size];
            if (rounded) return rounded;
        }
    }
    return font;
}

#pragma mark - 卡片

@interface HeliCardView ()
@property (nonatomic, strong) UIVisualEffectView *effectView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, strong) CAGradientLayer *hairline;
@end

@implementation HeliCardView

- (instancetype)initWithTitle:(NSString *)title footer:(NSString *)footer {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.layer.cornerRadius = 24.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.11].CGColor;

    _effectView = [[UIVisualEffectView alloc] initWithEffect:
                   [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    _effectView.translatesAutoresizingMaskIntoConstraints = NO;
    _effectView.layer.cornerRadius = 24.0;
    _effectView.layer.cornerCurve = kCACornerCurveContinuous;
    _effectView.clipsToBounds = YES;
    _effectView.userInteractionEnabled = NO;
    [self addSubview:_effectView];

    _hairline = [CAGradientLayer layer];
    _hairline.startPoint = CGPointMake(0.0, 0.5);
    _hairline.endPoint = CGPointMake(1.0, 0.5);
    _hairline.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                         (id)[UIColor colorWithWhite:1.0 alpha:0.34].CGColor,
                         (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    _hairline.locations = @[@0.0, @0.5, @1.0];
    [self.layer addSublayer:_hairline];

    _stack = [[UIStackView alloc] init];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 0.0;
    [_effectView.contentView addSubview:_stack];

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    [constraints addObjectsFromArray:@[
        [_effectView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_effectView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_effectView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_effectView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:_effectView.contentView.topAnchor constant:14.0],
        [_stack.bottomAnchor constraintEqualToAnchor:_effectView.contentView.bottomAnchor constant:-14.0],
        [_stack.leadingAnchor constraintEqualToAnchor:_effectView.contentView.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_effectView.contentView.trailingAnchor],
    ]];

    if (title.length > 0) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = HeliFont(13.0, UIFontWeightSemibold);
        _titleLabel.textColor = HeliTextTertiary();
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *wrap = [[UIView alloc] init];
        wrap.translatesAutoresizingMaskIntoConstraints = NO;
        [wrap addSubview:_titleLabel];
        [constraints addObjectsFromArray:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:18.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:wrap.trailingAnchor constant:-18.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:2.0],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-10.0],
        ]];
        [_stack addArrangedSubview:wrap];
    }

    if (footer.length > 0) {
        _footerLabel = [[UILabel alloc] init];
        _footerLabel.text = footer;
        _footerLabel.font = HeliFont(12.0, UIFontWeightRegular);
        _footerLabel.textColor = HeliTextTertiary();
        _footerLabel.numberOfLines = 0;
        _footerLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *wrap = [[UIView alloc] init];
        wrap.translatesAutoresizingMaskIntoConstraints = NO;
        [wrap addSubview:_footerLabel];
        [constraints addObjectsFromArray:@[
            [_footerLabel.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:18.0],
            [_footerLabel.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-18.0],
            [_footerLabel.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:12.0],
            [_footerLabel.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-4.0],
        ]];
        [_stack addArrangedSubview:wrap];
    }

    [NSLayoutConstraint activateConstraints:constraints];
    return self;
}

- (void)addRow:(UIView *)row {
    if (!row) return;
    // UIStackView 的 fill 对齐已经处理了宽度，不要再补 leading/trailing。
    [self.stack addArrangedSubview:row];
}

- (void)addSeparator {
    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.075];

    UIView *wrap = [[UIView alloc] init];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [wrap.heightAnchor constraintEqualToConstant:1.0],
        [line.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:18.0],
        [line.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-18.0],
        [line.topAnchor constraintEqualToAnchor:wrap.topAnchor],
        [line.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
    ]];
    [self.stack addArrangedSubview:wrap];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.hairline.frame = CGRectMake(18.0, 0.0, MAX(0.0, self.bounds.size.width - 36.0), 1.0);
}

@end

#pragma mark - 背景

@interface HeliBackdropView ()
@property (nonatomic, strong) CAGradientLayer *base;
@property (nonatomic, strong) CAGradientLayer *glowTop;
@property (nonatomic, strong) CAGradientLayer *glowBottom;
@end

@implementation HeliBackdropView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = [UIColor blackColor];

    _base = [CAGradientLayer layer];
    _base.colors = @[(id)[UIColor colorWithRed:0.043 green:0.055 blue:0.098 alpha:1.0].CGColor,
                     (id)[UIColor colorWithRed:0.055 green:0.078 blue:0.145 alpha:1.0].CGColor,
                     (id)[UIColor colorWithRed:0.027 green:0.035 blue:0.063 alpha:1.0].CGColor];
    _base.locations = @[@0.0, @0.52, @1.0];
    _base.startPoint = CGPointMake(0.1, 0.0);
    _base.endPoint = CGPointMake(0.9, 1.0);
    [self.layer addSublayer:_base];

    _glowTop = [CAGradientLayer layer];
    _glowTop.type = kCAGradientLayerRadial;
    _glowTop.colors = @[(id)[UIColor colorWithRed:0.20 green:0.62 blue:1.00 alpha:0.32].CGColor,
                        (id)[UIColor colorWithRed:0.20 green:0.62 blue:1.00 alpha:0.0].CGColor];
    _glowTop.locations = @[@0.0, @1.0];
    [self.layer addSublayer:_glowTop];

    _glowBottom = [CAGradientLayer layer];
    _glowBottom.type = kCAGradientLayerRadial;
    _glowBottom.colors = @[(id)[UIColor colorWithRed:0.58 green:0.38 blue:1.00 alpha:0.22].CGColor,
                           (id)[UIColor colorWithRed:0.58 green:0.38 blue:1.00 alpha:0.0].CGColor];
    _glowBottom.locations = @[@0.0, @1.0];
    [self.layer addSublayer:_glowBottom];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.base.frame = self.bounds;

    CGFloat width = self.bounds.size.width;
    CGFloat height = MAX(self.bounds.size.height, 1.0);
    self.glowTop.frame = CGRectMake(-width * 0.55, -height * 0.16, width * 1.9, width * 1.9);
    self.glowBottom.frame = CGRectMake(width * 0.10, height * 0.58, width * 1.6, width * 1.6);
    [CATransaction commit];
}

@end
