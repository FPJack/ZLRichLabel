//
//  OCDemoViewController.m
//  ZLRichLabel_Example
//
//  Objective-C 版演示页面：与 HTagDemoPage.swift 的 20 个用例一一对应
//

#import <UIKit/UIKit.h>
@import ZLRichLabel;

#pragma mark - 颜色

static UIColor *OCHex(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:1];
}

#define kBlue       OCHex(0x2196F3)
#define kDeepOrange OCHex(0xFF5722)
#define kRed        OCHex(0xF44336)
#define kGreen      OCHex(0x4CAF50)
#define kPurple     OCHex(0x9C27B0)
#define kDeepPurple OCHex(0x673AB7)
#define kOrange     OCHex(0xFF9800)
#define kGrey       OCHex(0x9E9E9E)
#define kTeal       OCHex(0x009688)
#define kPink       OCHex(0xE91E63)
#define kIndigo     OCHex(0x3F51B5)
#define kBrown      OCHex(0x795548)
#define kAmber      OCHex(0xFFC107)

static UIColor *OCDynamic(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return trait.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

static NSString *OCQuote(NSString *s) {
    return s ? [NSString stringWithFormat:@"\"%@\"", s] : @"null";
}

#pragma mark - 数据

@interface OCTapRecord : NSObject
@property (nonatomic, copy) NSString *caseName;
@property (nonatomic, strong) ZLTagInfo *info;
/// 触发的点击动作（tagTapHandlers 按标签名分发的结果）
@property (nonatomic, copy) NSString *action;
@property (nonatomic, strong) NSDate *time;
@end

@implementation OCTapRecord
@end

#pragma mark - 带内边距的 UILabel

@interface OCPaddingLabel : UILabel
@property (nonatomic, assign) UIEdgeInsets insets;
- (instancetype)initWithInsets:(UIEdgeInsets)insets;
@end

@implementation OCPaddingLabel

- (instancetype)initWithInsets:(UIEdgeInsets)insets {
    if (self = [super initWithFrame:CGRectZero]) {
        _insets = insets;
        self.textAlignment = NSTextAlignmentCenter;
    }
    return self;
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.insets)];
}

- (CGSize)sizeThatFits:(CGSize)size {
    return self.intrinsicContentSize;
}

- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(ceil(size.width + self.insets.left + self.insets.right),
                      ceil(size.height + self.insets.top + self.insets.bottom));
}

@end

#pragma mark - 自定义 Widget

@interface OCDemoWidgets : NSObject
@end

@implementation OCDemoWidgets

/// 可变宽度的色块（固定尺寸，点击时外部直接改 frame）
+ (ZLRichWidget *)growBox:(CGFloat)width target:(id)target action:(SEL)action {
    UIView *box = [UIView new];
    box.backgroundColor = kOrange;
    box.layer.cornerRadius = 4;
    [box addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:action]];
    return [[ZLRichWidget alloc] initWithView:box
                                       size:CGSizeMake(width, 16)
                                   position:ZLRichWidgetPositionReplace
                                  alignment:ZLRichWidgetAlignmentMiddle
                                   tappable:NO];
}

+ (NSString *)likeText:(NSInteger)likes {
    return [NSString stringWithFormat:@"👍 %ld", (long)likes];
}

/// 点赞计数（size 传 CGSizeZero 自动计算，文字变化后重新测量）
+ (ZLRichWidget *)likeCounter:(NSInteger)likes target:(id)target action:(SEL)action {
    OCPaddingLabel *counter = [[OCPaddingLabel alloc] initWithInsets:UIEdgeInsetsMake(1, 6, 1, 6)];
    counter.text = [self likeText:likes];
    counter.font = [UIFont systemFontOfSize:12];
    counter.textColor = UIColor.whiteColor;
    counter.backgroundColor = kPink;
    counter.layer.cornerRadius = 9;
    counter.layer.masksToBounds = YES;
    counter.userInteractionEnabled = YES;
    [counter addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:action]];
    return [[ZLRichWidget alloc] initWithView:counter
                                       size:CGSizeZero
                                   position:ZLRichWidgetPositionReplace
                                  alignment:ZLRichWidgetAlignmentMiddle
                                   tappable:NO];
}

/// 按钮样式（替换文字）
+ (ZLRichWidget *)button:(NSString *)title {
    OCPaddingLabel *button = [[OCPaddingLabel alloc] initWithInsets:UIEdgeInsetsMake(2, 10, 2, 10)];
    button.text = title;
    button.font = [UIFont systemFontOfSize:12];
    button.textColor = UIColor.whiteColor;
    button.backgroundColor = kBlue;
    button.layer.cornerRadius = 12;
    button.layer.masksToBounds = YES;
    return [[ZLRichWidget alloc] initWithView:button
                                       size:button.intrinsicContentSize
                                   position:ZLRichWidgetPositionReplace
                                  alignment:ZLRichWidgetAlignmentMiddle
                                   tappable:YES];
}

/// 红点（与文字间距 4）
+ (ZLRichWidget *)redDot:(ZLRichWidgetPosition)position {
    UIView *container = [UIView new];
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(2, 0, 8, 8)];
    dot.backgroundColor = kRed;
    dot.layer.cornerRadius = 4;
    [container addSubview:dot];
    return [ZLRichWidget widgetWithView:container size:CGSizeMake(12, 8) position:position];
}

/// VIP 徽章（与文字间距 4）
+ (ZLRichWidget *)vipBadge:(ZLRichWidgetPosition)position {
    OCPaddingLabel *badge = [[OCPaddingLabel alloc] initWithInsets:UIEdgeInsetsMake(0, 4, 0, 4)];
    badge.text = @"VIP";
    badge.font = [UIFont boldSystemFontOfSize:10];
    badge.textColor = UIColor.whiteColor;
    badge.backgroundColor = kAmber;
    badge.layer.cornerRadius = 4;
    badge.layer.masksToBounds = YES;
    CGSize size = badge.intrinsicContentSize;
    badge.frame = CGRectMake(2, 0, size.width, size.height);
    UIView *container = [UIView new];
    [container addSubview:badge];
    return [ZLRichWidget widgetWithView:container size:CGSizeMake(size.width + 4, size.height) position:position];
}

/// 勾选框（自己处理点击，不触发 onTagTap）
+ (ZLRichWidget *)checkbox:(BOOL)checked target:(id)target action:(SEL)action {
    UIView *container = [UIView new];
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(2, 0, 18, 18)];
    icon.image = [UIImage systemImageNamed:checked ? @"checkmark.circle.fill" : @"circle"];
    icon.tintColor = checked ? kGreen : kGrey;
    [container addSubview:icon];
    [container addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:target action:action]];
    return [[ZLRichWidget alloc] initWithView:container
                                       size:CGSizeMake(22, 18)
                                   position:ZLRichWidgetPositionReplace
                                  alignment:ZLRichWidgetAlignmentMiddle
                                   tappable:NO];
}

/// 图标 + 文字（tagSpanBuilder 使用，NSTextAttachment 会被组件自动转换为可点击的 View）
+ (NSAttributedString *)iconText:(NSString *)symbol text:(NSString *)text style:(NSDictionary *)style {
    UIImage *image = [[UIImage systemImageNamed:symbol] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!image) { return nil; }
    NSTextAttachment *attachment = [NSTextAttachment new];
    attachment.image = image;
    attachment.bounds = CGRectMake(0, 0, 16, 16);
    NSMutableAttributedString *result =
        [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
    [result addAttributes:style range:NSMakeRange(0, result.length)];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:style]];
    return result;
}

@end

#pragma mark - ZLTagInfo 表格

@interface OCInfoTable : NSObject
@end

@implementation OCInfoTable

/// ZLTagInfo 所有字段的表格展示（等宽字体对齐）
+ (NSAttributedString *)make:(ZLTagInfo *)info {
    NSArray<NSArray<NSString *> *> *rows = @[
        @[@"index", [NSString stringWithFormat:@"%ld", (long)info.index]],
        @[@"name", OCQuote(info.name)],
        @[@"level", info.level ? info.level.stringValue : @"null"],
        @[@"text", OCQuote(info.text)],
        @[@"raw", OCQuote(info.raw)],
    ];
    NSUInteger keyWidth = 0;
    for (NSArray *row in rows) { keyWidth = MAX(keyWidth, [row[0] length]); }
    keyWidth += 2;

    UIFont *font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    NSMutableAttributedString *result = [NSMutableAttributedString new];
    [rows enumerateObjectsUsingBlock:^(NSArray<NSString *> *row, NSUInteger i, BOOL *stop) {
        NSString *key = [row[0] stringByPaddingToLength:keyWidth withString:@" " startingAtIndex:0];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:key attributes:@{
            NSFontAttributeName: font, NSForegroundColorAttributeName: kDeepPurple}]];
        NSString *value = [row[1] stringByAppendingString:(i < rows.count - 1 ? @"\n" : @"")];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:value attributes:@{
            NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.blackColor}]];
    }];
    return result;
}

@end

#pragma mark - 顶部点击信息面板

@interface OCTapInfoPanel : UIView
@property (nonatomic, strong, nullable) OCTapRecord *record;
@end

@implementation OCTapInfoPanel {
    UILabel *_titleLabel;
    UILabel *_tableLabel;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = OCHex(0xF3F0FA);
        _titleLabel = [UILabel new];
        _titleLabel.numberOfLines = 0;
        _tableLabel = [UILabel new];
        _tableLabel.numberOfLines = 0;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _tableLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 6;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        ]];
        [self update];
    }
    return self;
}

- (void)setRecord:(OCTapRecord *)record {
    _record = record;
    [self update];
}

- (void)update {
    OCTapRecord *r = self.record;
    if (!r) {
        _titleLabel.text = @"👆 点击下方任意高亮文字，这里会显示点击得到的所有信息";
        _titleLabel.font = [UIFont systemFontOfSize:14];
        _titleLabel.textColor = [UIColor colorWithWhite:0 alpha:0.54];
        _tableLabel.hidden = YES;
        return;
    }
    _titleLabel.text = [NSString stringWithFormat:@"最近点击 · %@\n动作：%@", r.caseName, r.action];
    _titleLabel.font = [UIFont boldSystemFontOfSize:14];
    _titleLabel.textColor = UIColor.blackColor;
    _tableLabel.hidden = NO;
    _tableLabel.attributedText = [OCInfoTable make:r.info];
}

@end

#pragma mark - 卡片

@interface OCCardView : UIView
@property (nonatomic, strong, readonly) UIStackView *stack;
+ (UILabel *)label:(NSString *)text font:(UIFont *)font color:(UIColor *)color;
@end

@implementation OCCardView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.whiteColor;
        self.layer.cornerRadius = 12;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.08;
        self.layer.shadowRadius = 4;
        self.layer.shadowOffset = CGSizeMake(0, 1);

        _stack = [UIStackView new];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.alignment = UIStackViewAlignmentFill;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        ]];
    }
    return self;
}

+ (UILabel *)label:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

@end

/// 单个用例卡片：标题 + 原始字符串 + 渲染效果 + onParsed 结果
@interface OCDemoCard : OCCardView
@property (nonatomic, copy, nullable) NSArray<ZLTagInfo *> *parsed;
/// 基类 ZLRichLabel 用例：展示最终生效的规则命中
@property (nonatomic, copy, nullable) NSArray<ZLRichMatch *> *matches;
- (instancetype)initWithTitle:(NSString *)title source:(NSString *)source content:(UIView *)content;
@end

@implementation OCDemoCard {
    UILabel *_parsedTitle;
    UILabel *_parsedLabel;
}

- (instancetype)initWithTitle:(NSString *)title source:(NSString *)source content:(UIView *)content {
    if (self = [super initWithFrame:CGRectZero]) {
        UIColor *secondary = [UIColor colorWithWhite:0 alpha:0.45];
        _parsedTitle = [OCCardView label:@"" font:[UIFont systemFontOfSize:12] color:secondary];
        _parsedLabel = [OCCardView label:@""
                                    font:[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]
                                   color:[UIColor colorWithWhite:0 alpha:0.54]];

        UILabel *titleLabel = [OCCardView label:title font:[UIFont boldSystemFontOfSize:15] color:UIColor.blackColor];
        UILabel *sourceTitle = [OCCardView label:@"原始字符串：" font:[UIFont systemFontOfSize:12] color:secondary];

        // 可选中复制的原始字符串
        UITextView *sourceView = [UITextView new];
        sourceView.text = source;
        sourceView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        sourceView.editable = NO;
        sourceView.selectable = YES;
        sourceView.scrollEnabled = NO;
        sourceView.backgroundColor = OCHex(0xF5F5F5);
        sourceView.layer.cornerRadius = 6;
        sourceView.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4);

        UILabel *renderTitle = [OCCardView label:@"渲染效果：" font:[UIFont systemFontOfSize:12] color:secondary];

        UIStackView *stack = self.stack;
        [stack addArrangedSubview:titleLabel];
        [stack setCustomSpacing:8 afterView:titleLabel];
        [stack addArrangedSubview:sourceTitle];
        [stack setCustomSpacing:4 afterView:sourceTitle];
        [stack addArrangedSubview:sourceView];
        [stack setCustomSpacing:8 afterView:sourceView];
        [stack addArrangedSubview:renderTitle];
        [stack setCustomSpacing:4 afterView:renderTitle];
        [stack addArrangedSubview:content];
        [stack setCustomSpacing:8 afterView:content];
        [stack addArrangedSubview:_parsedTitle];
        [stack setCustomSpacing:4 afterView:_parsedTitle];
        [stack addArrangedSubview:_parsedLabel];
        [self updateParsed];
    }
    return self;
}

- (void)setParsed:(NSArray<ZLTagInfo *> *)parsed {
    _parsed = [parsed copy];
    [self updateParsed];
}

- (void)setMatches:(NSArray<ZLRichMatch *> *)matches {
    _matches = [matches copy];
    [self updateParsed];
}

- (void)updateParsed {
    NSArray<ZLTagInfo *> *parsed = self.parsed;
    NSArray<ZLRichMatch *> *matches = self.matches;
    if (!parsed && matches) {
        _parsedTitle.hidden = NO;
        _parsedLabel.hidden = matches.count == 0;
        _parsedTitle.text = [NSString stringWithFormat:@"规则命中 matches（共 %lu 个）：", (unsigned long)matches.count];
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (ZLRichMatch *m in matches) {
            [lines addObject:[NSString stringWithFormat:@"#%ld  [%@]  text=\"%@\"  priority=%ld",
                              (long)m.index, m.rule.name, m.text, (long)m.rule.priority]];
        }
        _parsedLabel.text = [lines componentsJoinedByString:@"\n"];
        return;
    }
    if (!parsed) {
        _parsedTitle.hidden = YES;
        _parsedLabel.hidden = YES;
        return;
    }
    _parsedTitle.hidden = NO;
    _parsedLabel.hidden = parsed.count == 0;
    _parsedTitle.text = [NSString stringWithFormat:@"onParsed 回调（共 %lu 个标签）：", (unsigned long)parsed.count];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (ZLTagInfo *t in parsed) {
        // 嵌套的标签按深度缩进，有属性时一并显示
        NSString *indent = [@"" stringByPaddingToLength:t.depth * 4 withString:@" " startingAtIndex:0];
        NSString *level = [t.name hasPrefix:@"h"]
            ? [NSString stringWithFormat:@"  level=%@", t.level ? t.level.stringValue : @"null"] : @"";
        NSMutableArray<NSString *> *pairs = [NSMutableArray array];
        for (NSString *key in [t.attributes.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [pairs addObject:[NSString stringWithFormat:@"%@=\"%@\"", key, t.attributes[key]]];
        }
        NSString *attrs = pairs.count ? [@"  attributes=" stringByAppendingString:[pairs componentsJoinedByString:@" "]] : @"";
        [lines addObject:[NSString stringWithFormat:@"%@#%ld  <%@>  text=\"%@\"%@%@",
                          indent, (long)t.index, t.name, t.text, level, attrs]];
    }
    _parsedLabel.text = [lines componentsJoinedByString:@"\n"];
}

@end

/// 点击历史
@interface OCHistoryCard : OCCardView
@property (nonatomic, copy) NSArray<OCTapRecord *> *history;
@end

@implementation OCHistoryCard {
    UILabel *_titleLabel;
    UILabel *_contentLabel;
}

+ (NSDateFormatter *)formatter {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new];
        f.dateFormat = @"HH:mm:ss";
    });
    return f;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _history = @[];
        _titleLabel = [OCCardView label:@"" font:[UIFont boldSystemFontOfSize:15] color:UIColor.blackColor];
        _contentLabel = [OCCardView label:@""
                                     font:[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]
                                    color:UIColor.blackColor];
        self.stack.spacing = 6;
        [self.stack addArrangedSubview:_titleLabel];
        [self.stack addArrangedSubview:_contentLabel];
        [self update];
    }
    return self;
}

- (void)setHistory:(NSArray<OCTapRecord *> *)history {
    _history = [history copy];
    [self update];
}

- (void)update {
    _titleLabel.text = [NSString stringWithFormat:@"点击历史（%lu）", (unsigned long)self.history.count];
    if (self.history.count == 0) {
        _contentLabel.attributedText = nil;
        _contentLabel.text = @"暂无";
        _contentLabel.font = [UIFont systemFontOfSize:14];
        _contentLabel.textColor = [UIColor colorWithWhite:0 alpha:0.45];
        return;
    }

    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.paragraphSpacing = 4;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (OCTapRecord *r in self.history) {
        NSString *caseNo = [r.caseName componentsSeparatedByString:@" "].firstObject ?: @"";
        [lines addObject:[NSString stringWithFormat:@"%@  %@ <%@> index=%ld text=\"%@\" action=%@",
                          [OCHistoryCard.formatter stringFromDate:r.time], caseNo,
                          r.info.name, (long)r.info.index, r.info.text, r.action]];
    }
    _contentLabel.attributedText = [[NSAttributedString alloc]
        initWithString:[lines componentsJoinedByString:@"\n"]
            attributes:@{
                NSFontAttributeName: [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular],
                NSForegroundColorAttributeName: UIColor.blackColor,
                NSParagraphStyleAttributeName: paragraph,
            }];
}

@end

#pragma mark - 页面

@interface OCDemoViewController : UIViewController
@end

@interface OCDemoViewController ()
/// 最近一次点击
@property (nonatomic, strong, nullable) OCTapRecord *last;
/// 点击历史
@property (nonatomic, strong) NSMutableArray<OCTapRecord *> *history;
@property (nonatomic, strong) OCTapInfoPanel *tapInfoPanel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) OCHistoryCard *historyCard;
/// 每个用例的卡片（用于显示 onParsed 结果）
@property (nonatomic, strong) NSMutableDictionary<NSString *, OCDemoCard *> *cards;
/// 用例 11 / 16 的勾选状态
@property (nonatomic, assign) BOOL agreed11;
@property (nonatomic, assign) BOOL agreed16;
@property (nonatomic, weak) ZLTagRichLabel *case11Label;
@property (nonatomic, weak) ZLTagRichLabel *case16Label;
/// 用例 21 的状态（label rebuild 时 builder 会按状态重新创建 View）
@property (nonatomic, assign) CGFloat boxWidth21;
@property (nonatomic, assign) NSInteger likes21;
/// 用例 22：外观 / 字号覆盖只作用在预览区域
@property (nonatomic, weak) UIView *case22Preview;
@property (nonatomic, weak) ZLTagRichLabel *case22Label;
/// 用例 23：性能（渲染缓存 / 排版缓存）
@property (nonatomic, weak) ZLRichLabel *case23Label;
@property (nonatomic, weak) UILabel *case23Stats;
@property (nonatomic, assign) BOOL mentionGreen23;
@property (nonatomic, assign) BOOL highlightBlue23;
@property (nonatomic, assign) NSInteger appended23;
/// 用例 25：长按菜单从手势位置弹出
@property (nonatomic, weak) ZLTagRichLabel *case25Label;
/// 用例 30：首 / 中 / 尾自定义 View 跟随 label 尺寸
@property (nonatomic, weak) ZLRichLabel *case30Label;
@property (nonatomic, weak) NSLayoutConstraint *case30Width;
@property (nonatomic, weak) UISlider *case30Slider;
@property (nonatomic, weak) UILabel *case30Status;
/// @[标题, View]，按文本中出现的顺序
@property (nonatomic, copy) NSArray<NSArray *> *case30Views;
@property (nonatomic, assign) BOOL case30Followed;
@end

@implementation OCDemoViewController

+ (NSDictionary<NSAttributedStringKey, id> *)baseStyle {
    return @{NSFontAttributeName: [UIFont systemFontOfSize:15],
             NSForegroundColorAttributeName: [UIColor colorWithWhite:0 alpha:0.87]};
}

#pragma mark Life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HTagRichText Demo (OC)";
    self.view.backgroundColor = OCHex(0xFEF7FF);
    self.history = [NSMutableArray array];
    self.cards = [NSMutableDictionary dictionary];
    self.boxWidth21 = 24;

    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                           target:self
                                                                           action:@selector(clearHistory)];
    clear.accessibilityLabel = @"清空点击记录";
    self.navigationItem.rightBarButtonItem = clear;

    [self setupLayout];

    [self case1];
    [self case2];
    [self case3];
    [self case4];
    [self case5];
    [self case6];
    [self case7];
    [self case8];
    [self case9];
    [self case10];
    [self case11];
    // 阿拉伯语（RTL）
    [self case12];
    [self case13];
    [self case14];
    [self case15];
    [self case16];
    // 自定义正则规则
    [self case17];
    [self case18];
    [self case19];
    [self case20];
    // 自定义 View 尺寸变化
    [self case21];
    // 深色模式 / Dynamic Type
    [self case22];
    // 性能：渲染缓存 / 排版缓存
    [self case23];
    // 展开 / 收起
    [self case24];
    // 长按 / 双击 / 扩大点击热区
    [self case25];
    // 选中复制
    [self case26];
    // 通用标签：任意标签名 / 属性 / 嵌套
    [self case27];
    // 胶囊背景 / 渐变文字
    [self case28];
    [self case28b];
    // 首 / 中 / 尾自定义 View 跟随 label 尺寸
    [self case30];
    [self.stackView addArrangedSubview:self.historyCard];

    [self refreshTapViews];
}

- (void)setupLayout {
    self.tapInfoPanel = [OCTapInfoPanel new];
    self.scrollView = [UIScrollView new];
    self.stackView = [UIStackView new];
    self.historyCard = [OCHistoryCard new];

    UIView *divider = [UIView new];
    divider.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];

    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 12;
    self.stackView.alignment = UIStackViewAlignmentFill;

    for (UIView *v in @[self.tapInfoPanel, divider, self.scrollView]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:v];
    }
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stackView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UIScrollView *scroll = self.scrollView;
    [NSLayoutConstraint activateConstraints:@[
        [self.tapInfoPanel.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tapInfoPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tapInfoPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [divider.topAnchor constraintEqualToAnchor:self.tapInfoPanel.bottomAnchor],
        [divider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [divider.heightAnchor constraintEqualToConstant:1],

        [scroll.topAnchor constraintEqualToAnchor:divider.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.stackView.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [self.stackView.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-12],
        [self.stackView.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:12],
        [self.stackView.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-12],
    ]];
}

#pragma mark Events

- (void)onTap:(NSString *)caseName info:(ZLTagInfo *)info action:(nullable NSString *)action {
    OCTapRecord *record = [OCTapRecord new];
    record.caseName = caseName;
    record.info = info;
    record.action = action ?: @"onTagTap（兜底）";
    record.time = [NSDate date];
    self.last = record;
    [self.history insertObject:record atIndex:0];
    if (self.history.count > 20) { [self.history removeLastObject]; }
    NSLog(@"[%@] %@ -> %@", caseName, record.action, info);
    [self refreshTapViews];
}

- (void)onParsed:(NSString *)caseName tags:(NSArray<ZLTagInfo *> *)tags {
    self.cards[caseName].parsed = tags;
}

- (void)clearHistory {
    self.last = nil;
    [self.history removeAllObjects];
    [self refreshTapViews];
}

- (void)refreshTapViews {
    self.tapInfoPanel.record = self.last;
    self.historyCard.history = self.history;
}

/// 自定义规则点击 → 记录到点击面板。
/// 注意：不要在 onTap 里强引用 ctx（ctx 持有 onTap 会循环引用），这里提前取出需要的值
/// 规则点击：onTap 的参数就是这次点击的命中，block 里不需要（也不要）引用 ctx
- (void (^)(ZLRichMatch *))ruleTapForCase:(NSString *)caseName action:(NSString *)action {
    __weak typeof(self) weakSelf = self;
    return ^(ZLRichMatch *match) {
        [weakSelf onTap:caseName info:[OCDemoViewController infoForMatch:match] action:action];
    };
}

+ (ZLTagInfo *)infoForMatch:(ZLRichMatch *)match {
    return [[ZLTagInfo alloc] initWithIndex:match.index name:[@"rule:" stringByAppendingString:match.rule.name]
                                      text:match.text raw:match.text];
}

#pragma mark Helper

/// 添加一个用例卡片：标题 + 原始字符串 + 渲染效果 + onParsed 结果
- (ZLTagRichLabel *)addCase:(NSString *)name
                     source:(NSString *)source
                   tappable:(BOOL)tappable
                  configure:(void (^)(ZLTagRichLabel *v))configure {
    ZLTagRichLabel *label = [[ZLTagRichLabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.verticalAlignment = ZLLabelVerticalAlignmentTop;

    __weak typeof(self) weakSelf = self;
    // updateTag: 的回调参数直接是 ZLTagRichLabel，不需要强转
    [label updateTag:^(ZLTagRichLabel *v) {
        v.style = OCDemoViewController.baseStyle;
        if (tappable) {
            v.onTagTap = ^(ZLTagInfo *info) { [weakSelf onTap:name info:info action:nil]; };
        }
        v.onParsed = ^(NSArray<ZLTagInfo *> *tags) { [weakSelf onParsed:name tags:tags]; };
        configure(v);
        v.text = source; // 等同于 v.tagText = source
    }];

    OCDemoCard *card = [[OCDemoCard alloc] initWithTitle:name source:source content:label];
    self.cards[name] = card;
    [self.stackView addArrangedSubview:card];
    return label;
}

- (ZLTagRichLabel *)addCase:(NSString *)name source:(NSString *)source configure:(void (^)(ZLTagRichLabel *v))configure {
    return [self addCase:name source:source tappable:YES configure:configure];
}

/// 添加一个纯自定义规则的用例：直接使用基类 ZLRichLabel（不解析 <h> 标签）
/// 卡片底部展示最终生效的规则命中（解析是同步的，设置 text 后即可读取 matches）
- (ZLRichLabel *)addRuleCase:(NSString *)name source:(NSString *)source configure:(void (^)(ZLRichLabel *v))configure {
    ZLRichLabel *label = [[ZLRichLabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.verticalAlignment = ZLLabelVerticalAlignmentTop;
    [label update:^(ZLRichLabel *v) {
        v.style = OCDemoViewController.baseStyle;
        configure(v);
        v.text = source; // 等同于 v.rawText = source
    }];

    OCDemoCard *card = [[OCDemoCard alloc] initWithTitle:name source:source content:label];
    card.matches = label.matches;
    self.cards[name] = card;
    [self.stackView addArrangedSubview:card];
    return label;
}

#pragma mark - 各用例

/// 1. 按标签名区分样式（tagStyles）
- (void)case1 {
    [self addCase:@"1. 按标签名区分样式（h1 / h2）"
           source:@"By logging in or registering an account, you agree to the "
                  @"<h1>User Agreement</h1> and <h2>Privacy Policy</h2>."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]};
        v.tagStyles = @{
            @"h1": @{NSForegroundColorAttributeName: kBlue,
                     NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                     NSUnderlineColorAttributeName: kBlue},
            @"h2": @{NSForegroundColorAttributeName: kDeepOrange},
        };
    }];
}

/// 2. 只用 <h>，按 index 区分样式（tagStyleBuilder）
- (void)case2 {
    NSArray<UIColor *> *colors = @[kRed, kGreen, kPurple];
    [self addCase:@"2. 同名标签 <h>，按 index 区分样式"
           source:@"Fruits: <h>Apple</h>, <h>Banana<h/> and <h>Cherry</h>."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyleBuilder = ^NSDictionary<NSAttributedStringKey, id> *(ZLTagInfo *info) {
            return @{NSForegroundColorAttributeName: colors[info.index % colors.count],
                     NSFontAttributeName: [UIFont boldSystemFontOfSize:15]};
        };
    }];
}

/// 3. 多种标签名 + 两种闭合写法 + 大小写
- (void)case3 {
    [self addCase:@"3. h / h1 / h2 / h3 / H4，</hN> 与 <hN/> 闭合"
           source:@"<h>Default</h>, <h1>Level one<h1/>, <h2>Level two</h2>, "
                  @"<h3>Level three<h3/> and <H4>Upper case</H4>."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.tagStyles = @{
            @"h1": @{NSFontAttributeName: [UIFont boldSystemFontOfSize:15],
                     NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)},
            @"h2": @{NSForegroundColorAttributeName: kGreen,
                     NSFontAttributeName: [UIFont italicSystemFontOfSize:15]},
            @"h3": @{NSForegroundColorAttributeName: kPurple,
                     NSBackgroundColorAttributeName: OCHex(0xEDE7F6)},
            @"h4": @{NSForegroundColorAttributeName: kRed,
                     NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)},
        };
    }];
}

/// 4. 按标签名区分点击（setTapHandler:forTag:），没有 handler 的走 onTagTap 兜底
- (void)case4 {
    NSString *name = @"4. 按标签名区分点击（tagTapHandlers）";
    __weak typeof(self) weakSelf = self;
    [self addCase:name
           source:@"Read <h1>User Agreement</h1>, <h2>Privacy Policy</h2> "
                  @"and <h3>FAQ</h3> (h3 has no handler → onTagTap)."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyles = @{
            @"h1": @{NSForegroundColorAttributeName: kBlue},
            @"h2": @{NSForegroundColorAttributeName: kDeepOrange},
            @"h3": @{NSForegroundColorAttributeName: kTeal},
        };
        [v setTapHandler:^(ZLTagInfo *info) {
            [weakSelf onTap:name info:info action:@"h1 handler → 打开用户协议"];
        } forTag:@"h1"];
        [v setTapHandler:^(ZLTagInfo *info) {
            [weakSelf onTap:name info:info action:@"h2 handler → 打开隐私政策"];
        } forTag:@"h2"];
    }];
}

/// 5. 按标签名区分按下高亮（tagHighlightStyles）
- (void)case5 {
    [self addCase:@"5. 按标签名区分按下高亮（长按查看）"
           source:@"Press and hold: <h1>Yellow bg</h1> / <h2>Red text</h2> / "
                  @"<h3>No highlight</h3> / <h>Default grey</h>."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.tagHighlightStyle = @{NSBackgroundColorAttributeName: OCHex(0xE0E0E0)}; // 默认（<h>）
        v.tagHighlightStyles = @{
            @"h1": @{NSBackgroundColorAttributeName: OCHex(0xFFF59D)},
            @"h2": @{NSForegroundColorAttributeName: kRed,
                     NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)},
            @"h3": @{}, // 不高亮
        };
    }];
}

/// 6. 容错：[] 原样展示 / 开闭不匹配 / 未闭合 / 嵌套 / 非 h 标签
- (void)case6 {
    [self addCase:@"6. 容错：[] 原样 / 不匹配 / 未闭合 / 嵌套"
           source:@"Brackets kept: <h1>Terms[1]</h1>; mismatched: <h1>X</h2>; "
                  @"unclosed: <h2>Y; nested: <h1>a<h2>b</h2>c</h1>; not h: <hx>no</hx>."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyles = @{
            @"h1": @{NSForegroundColorAttributeName: kTeal, NSFontAttributeName: [UIFont boldSystemFontOfSize:15]},
            @"h2": @{NSForegroundColorAttributeName: kPink, NSFontAttributeName: [UIFont boldSystemFontOfSize:15]},
        };
    }];
}

/// 7. tagSpanBuilder：按标签名加图标
- (void)case7 {
    NSDictionary<NSString *, NSString *> *icons = @{@"h1": @"doc.text.fill", @"h2": @"lock.shield.fill"};
    [self addCase:@"7. tagSpanBuilder 按标签名加图标"
           source:@"Please read <h1>User Agreement</h1> and "
                  @"<h2>Privacy Policy</h2> carefully, or <h>skip</h>."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSForegroundColorAttributeName: kIndigo};
        v.tagSpanBuilder = ^NSAttributedString *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            NSString *icon = icons[info.name];
            if (!icon) { return nil; } // 返回 nil 使用默认样式
            return [OCDemoWidgets iconText:icon text:[NSString stringWithFormat:@"《%@》", info.text] style:style];
        };
    }];
}

/// 8. 无点击事件
- (void)case8 {
    [self addCase:@"8. 无点击（无 onTagTap / tagTapHandlers）"
           source:@"Plain text. <h1>Not clickable</h1> and <h2>neither</h2>."
         tappable:NO
        configure:^(ZLTagRichLabel *v) {
        v.tagStyles = @{@"h1": @{NSForegroundColorAttributeName: kBrown},
                        @"h2": @{NSForegroundColorAttributeName: kGrey}};
    }];
}

/// 9. 多行 + maxLines 省略
- (void)case9 {
    [self addCase:@"9. maxLines = 2 + 省略号"
           source:@"This is a very long text to demonstrate the maxLines and "
                  @"overflow parameters. <h1>First</h1> link, some more words, "
                  @"<h2>Second</h2> link, and even more words that will be cut off "
                  @"here <h3>Hidden</h3>."
        configure:^(ZLTagRichLabel *v) {
        v.numberOfLines = 2;
        v.lineBreakMode = NSLineBreakByTruncatingTail;
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
    }];
}

/// 10. tagWidgetBuilder：按标签名展示不同的自定义 View
- (void)case10 {
    [self addCase:@"10. tagWidgetBuilder 按标签名自定义 View"
           source:@"Replace: <h1>Follow</h1>  Before: <h2>Hot topic</h2>  "
                  @"After: <h3>Alice</h3>  Default: <h>Plain</h>"
        configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.tagWidgetBuilder = ^ZLRichWidget *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            if ([info.name isEqualToString:@"h1"]) { // 替换文字
                return [OCDemoWidgets button:[NSString stringWithFormat:@"+ %@ #%ld", info.text, (long)info.index]];
            }
            if ([info.name isEqualToString:@"h2"]) { return [OCDemoWidgets redDot:ZLRichWidgetPositionBefore]; }  // 文字前
            if ([info.name isEqualToString:@"h3"]) { return [OCDemoWidgets vipBadge:ZLRichWidgetPositionAfter]; } // 文字后
            return nil; // 默认文字
        };
    }];
}

/// 11. View 自己处理交互（tappable: NO）
- (void)case11 {
    __weak typeof(self) weakSelf = self;
    self.case11Label = [self addCase:@"11. Widget 自带交互 (tappable: NO)"
                              source:@"<h0>check</h0> I have read and agree to the "
                                     @"<h1>User Agreement</h1> and <h2>Privacy Policy</h2>."
                           configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.tagWidgetBuilder = ^ZLRichWidget *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            OCDemoViewController *strongSelf = weakSelf;
            if (!strongSelf || ![info.name isEqualToString:@"h0"]) { return nil; }
            return [OCDemoWidgets checkbox:strongSelf.agreed11 target:strongSelf action:@selector(toggleAgree11)];
        };
    }];
}

- (void)toggleAgree11 {
    self.agreed11 = !self.agreed11;
    [self.case11Label rebuild];
}

#pragma mark - 阿拉伯语（RTL）用例

/// 12. 阿拉伯语：按标签名区分样式与点击
- (void)case12 {
    NSString *name = @"12. 阿拉伯语：按标签名区分样式与点击";
    __weak typeof(self) weakSelf = self;
    [self addCase:name
           source:@"بتسجيل الدخول أو إنشاء حساب، فإنك توافق على "
                  @"<h1>اتفاقية المستخدم</h1> و<h2>سياسة الخصوصية</h2>."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]};
        v.tagStyles = @{
            @"h1": @{NSForegroundColorAttributeName: kBlue,
                     NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)},
            @"h2": @{NSForegroundColorAttributeName: kDeepOrange},
        };
        [v setTapHandler:^(ZLTagInfo *info) {
            [weakSelf onTap:name info:info action:@"h1 handler → اتفاقية المستخدم"];
        } forTag:@"h1"];
        [v setTapHandler:^(ZLTagInfo *info) {
            [weakSelf onTap:name info:info action:@"h2 handler → سياسة الخصوصية"];
        } forTag:@"h2"];
    }];
}

/// 13. 阿拉伯语 + 英文混排（双向文本）
- (void)case13 {
    [self addCase:@"13. 阿拉伯语 + 英文混排"
           source:@"اقرأ <h1>Terms of Service</h1> ثم <h2>الأسئلة الشائعة</h2> "
                  @"وتواصل مع <h3>Support Team</h3> أو <h>نحن</h>."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.tagStyles = @{
            @"h1": @{NSFontAttributeName: [UIFont boldSystemFontOfSize:15],
                     NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)},
            @"h2": @{NSBackgroundColorAttributeName: OCHex(0xE0E0E0)},
            @"h3": @{NSForegroundColorAttributeName: kGreen},
        };
    }];
}

/// 14. 阿拉伯语多行 + maxLines 省略
- (void)case14 {
    [self addCase:@"14. 阿拉伯语 maxLines = 2 + 省略号"
           source:@"هذا نص طويل جدًا لإظهار خاصية الحد الأقصى لعدد الأسطر. "
                  @"<h1>الرابط الأول</h1> بعض الكلمات الإضافية، "
                  @"<h2>الرابط الثاني</h2> والمزيد من الكلمات التي سيتم قطعها هنا "
                  @"<h3>مخفي</h3>."
        configure:^(ZLTagRichLabel *v) {
        v.numberOfLines = 2;
        v.lineBreakMode = NSLineBreakByTruncatingTail;
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
    }];
}

/// 15. 阿拉伯语 + 按标签名自定义 View / 图标
- (void)case15 {
    [self addCase:@"15. 阿拉伯语 + 自定义 Widget / 图标"
           source:@"تابع: <h1>متابعة</h1>  جديد: <h2>موضوع رائج</h2>  "
                  @"مميز: <h3>علي</h3>  اقرأ <h4>الاتفاقية</h4>."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.tagSpanBuilder = ^NSAttributedString *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            if (![info.name isEqualToString:@"h4"]) { return nil; }
            return [OCDemoWidgets iconText:@"doc.text.fill" text:[NSString stringWithFormat:@"«%@»", info.text] style:style];
        };
        v.tagWidgetBuilder = ^ZLRichWidget *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            if ([info.name isEqualToString:@"h1"]) {
                return [OCDemoWidgets button:[NSString stringWithFormat:@"+ %@", info.text]];
            }
            if ([info.name isEqualToString:@"h2"]) { return [OCDemoWidgets redDot:ZLRichWidgetPositionBefore]; }
            if ([info.name isEqualToString:@"h3"]) { return [OCDemoWidgets vipBadge:ZLRichWidgetPositionAfter]; }
            return nil;
        };
    }];
}

/// 16. 阿拉伯语 + 勾选框（tappable: NO）
- (void)case16 {
    __weak typeof(self) weakSelf = self;
    self.case16Label = [self addCase:@"16. 阿拉伯语 + 勾选框 (tappable: NO)"
                              source:@"<h0>check</h0> لقد قرأت وأوافق على "
                                     @"<h1>اتفاقية المستخدم</h1> و<h2>سياسة الخصوصية</h2>."
                           configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.tagWidgetBuilder = ^ZLRichWidget *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            OCDemoViewController *strongSelf = weakSelf;
            if (!strongSelf || ![info.name isEqualToString:@"h0"]) { return nil; }
            return [OCDemoWidgets checkbox:strongSelf.agreed16 target:strongSelf action:@selector(toggleAgree16)];
        };
    }];
}

- (void)toggleAgree16 {
    self.agreed16 = !self.agreed16;
    [self.case16Label rebuild];
}

#pragma mark - 自定义正则规则用例

/// 17. 自定义规则（基类 ZLRichLabel）：@提及 / #话题# / 链接（NSDataDetector）
- (void)case17 {
    NSString *name = @"17. ZLRichLabel 自定义规则：@提及 / #话题# / 链接";
    __weak typeof(self) weakSelf = self;
    [self addRuleCase:name
               source:@"Hi @alice and @bob_99, join #SwiftUI# talk: https://www.apple.com/swift"
            configure:^(ZLRichLabel *v) {
        // @提及
        [v addRuleWithName:@"mention" pattern:@"@\\w+" options:0 priority:10 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx addAttributes:@{NSForegroundColorAttributeName: kPurple,
                                 NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]}];
            NSString *action = [NSString stringWithFormat:@"mention → 打开 %@ 的主页", ctx.matchedText];
            ctx.onTap = [weakSelf ruleTapForCase:name action:action];
        }];
        // #话题#
        [v addRuleWithName:@"topic" pattern:@"#[^#\\s]+#" options:0 priority:10 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx addAttributes:@{NSForegroundColorAttributeName: kDeepOrange}];
            ctx.highlightStyle = @{NSBackgroundColorAttributeName: OCHex(0xFFE0B2)};
            NSString *action = [NSString stringWithFormat:@"topic → 打开话题 %@", ctx.matchedText];
            ctx.onTap = [weakSelf ruleTapForCase:name action:action];
        }];
        // 链接：NSDataDetector 也是 NSRegularExpression，替换展示文字
        NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
        if (detector) {
            [v addRule:[[ZLRichRule alloc] initWithName:@"link" regex:detector priority:10
                                                 handler:^(ZLRichRuleContext *ctx) {
                NSString *url = ctx.match.result.URL.absoluteString ?: ctx.matchedText;
                [ctx setText:@"🔗网页链接" attributes:@{NSForegroundColorAttributeName: kBlue,
                                                    NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)}];
                NSString *action = [NSString stringWithFormat:@"link → 打开 %@", url];
                ctx.onTap = [weakSelf ruleTapForCase:name action:action];
            }]];
        }
    }];
}

/// 18. 外部解析后替换内容（基类 ZLRichLabel）：表情图片 / 模板变量（命名捕获组）
- (void)case18 {
    NSString *name = @"18. ZLRichLabel 外部解析替换：[smile] 表情 / {{变量}}";
    NSDictionary<NSString *, NSString *> *symbols = @{@"smile": @"face.smiling", @"heart": @"heart.fill", @"star": @"star.fill"};
    NSDictionary<NSString *, UIColor *> *colors = @{@"smile": kOrange, @"heart": kRed, @"star": kAmber};
    NSDictionary<NSString *, NSString *> *variables = @{@"name": @"Alice", @"count": @"3"};
    __weak typeof(self) weakSelf = self;
    [self addRuleCase:name
               source:@"Hello {{name}} [smile], you have {{count}} new messages [heart][star]. "
                      @"Unknown: {{foo}} [xxx]."
            configure:^(ZLRichLabel *v) {
        // 表情：把 [smile] 替换为图片（NSTextAttachment 会被自动转换为 View），点击图片也能响应
        [v addRuleWithName:@"emoji" pattern:@"\\[(smile|heart|star)\\]" options:0 priority:5 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            NSString *key = [ctx groupAtIndex:1];
            NSString *symbol = key ? symbols[key] : nil;
            if (!symbol) { return; }
            UIImage *image = [[UIImage systemImageNamed:symbol] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            if (!image) { return; }
            NSTextAttachment *attachment = [NSTextAttachment new];
            attachment.image = image;
            attachment.bounds = CGRectMake(0, 0, 17, 17);
            NSMutableAttributedString *content = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
            [content addAttributes:@{NSForegroundColorAttributeName: colors[key] ?: kGrey}
                             range:NSMakeRange(0, content.length)];
            [ctx.attributedString setAttributedString:content];
            ctx.onTap = [weakSelf ruleTapForCase:name action:[@"emoji → " stringByAppendingString:key]];
        }];
        // 模板变量：命名捕获组取 key，外部查值后写回
        [v addRuleWithName:@"variable" pattern:@"\\{\\{(?<key>\\w+)\\}\\}" options:0 priority:5 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            NSString *value = variables[[ctx groupNamed:@"key"] ?: @""];
            if (value) {
                [ctx setText:value attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:15],
                                                NSForegroundColorAttributeName: kTeal}];
            } else {
                [ctx addAttributes:@{NSForegroundColorAttributeName: kGrey,
                                     NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)}];
            }
        }];
    }];
}

/// 19. 优先级：手机号规则(20) > <h> 标签(tagPriority) > 数字规则(1)
/// 需要和 <h> 标签比较优先级，所以这里用 ZLTagRichLabel
- (void)case19 {
    NSString *source = @"Call <h1>13800138000</h1> or 400-123-4567, order 2024.";
    __weak typeof(self) weakSelf = self;
    void (^configure)(ZLTagRichLabel *, NSString *) = ^(ZLTagRichLabel *v, NSString *name) {
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue,
                       NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)};
        [v addRuleWithName:@"phone" pattern:@"1\\d{10}" options:0 priority:20 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx addAttributes:@{NSForegroundColorAttributeName: kGreen,
                                 NSFontAttributeName: [UIFont boldSystemFontOfSize:15]}];
            NSString *action = [NSString stringWithFormat:@"phone(20) → 拨打 %@", ctx.matchedText];
            ctx.onTap = [weakSelf ruleTapForCase:name action:action];
        }];
        [v addRuleWithName:@"number" pattern:@"\\d+" options:0 priority:1 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx addAttributes:@{NSBackgroundColorAttributeName: OCHex(0xE0E0E0)}];
        }];
    };

    NSString *nameA = @"19a. 优先级：phone(20) > h1(0) > number(1)?";
    [self addCase:nameA source:source configure:^(ZLTagRichLabel *v) {
        v.tagPriority = 0; // h1 与 phone 重叠，phone 优先级更高 → h1 整体作废，<h1> 原样显示
        configure(v, nameA);
    }];
    NSString *nameB = @"19b. 优先级：h1(100) > phone(20) > number(1)";
    [self addCase:nameB source:source configure:^(ZLTagRichLabel *v) {
        v.tagPriority = 100; // h1 优先，内部的手机号不再被规则处理
        configure(v, nameB);
    }];
}

/// 20. 只用自定义规则（基类 ZLRichLabel，不解析 <h> 标签）：简易 Markdown
- (void)case20 {
    [self addRuleCase:@"20. ZLRichLabel 简易 Markdown（<h> 不解析）"
               source:@"<h1>not parsed</h1>, **bold**, ~~strike~~, `code` and **nested `x`**."
            configure:^(ZLRichLabel *v) {
        // 长的 **...** 先占位（同优先级位置靠前 / 更长优先），内部的 `x` 不会再被处理
        [v addRuleWithName:@"bold" pattern:@"\\*\\*(.+?)\\*\\*" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx setText:[ctx groupAtIndex:1] ?: @"" attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:15]}];
        }];
        [v addRuleWithName:@"strike" pattern:@"~~(.+?)~~" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx setText:[ctx groupAtIndex:1] ?: @""
              attributes:@{NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle)}];
        }];
        [v addRuleWithName:@"code" pattern:@"`([^`]+)`" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx setText:[ctx groupAtIndex:1] ?: @"" attributes:@{
                NSFontAttributeName: [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular],
                NSBackgroundColorAttributeName: OCHex(0xEEEEEE),
                NSForegroundColorAttributeName: kPink,
            }];
        }];
    }];
}

#pragma mark - 自定义 View 尺寸变化

/// 21. 自定义 View 尺寸 / 内容变化后，label 自动重新排版
- (void)case21 {
    __weak typeof(self) weakSelf = self;
    [self addCase:@"21. 自定义 View 尺寸变化，自动刷新排版"
           source:@"Tap the box <h1>box</h1> to resize it, tap <h2>like</h2> to add likes, "
                  @"the following text reflows automatically."
        configure:^(ZLTagRichLabel *v) {
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.tagWidgetBuilder = ^ZLRichWidget *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            OCDemoViewController *strongSelf = weakSelf;
            if (!strongSelf) { return nil; }
            if ([info.name isEqualToString:@"h1"]) {
                return [OCDemoWidgets growBox:strongSelf.boxWidth21 target:strongSelf action:@selector(growBox21:)];
            }
            if ([info.name isEqualToString:@"h2"]) {
                return [OCDemoWidgets likeCounter:strongSelf.likes21 target:strongSelf action:@selector(like21:)];
            }
            return nil;
        };
    }];
}

/// 直接修改 View 的 frame 尺寸：label 下次布局时自动检测并重新排版，无需额外调用
- (void)growBox21:(UITapGestureRecognizer *)gesture {
    UIView *box = gesture.view;
    if (!box) { return; }
    self.boxWidth21 = self.boxWidth21 >= 120 ? 24 : self.boxWidth21 + 32;
    CGRect frame = box.frame;
    frame.size.width = self.boxWidth21;
    box.frame = frame;
}

/// 自动尺寸（size 为 CGSizeZero）的 View 内容变化：调用 zl_setNeedsRichLabelLayout 重新测量
- (void)like21:(UITapGestureRecognizer *)gesture {
    if (![gesture.view isKindOfClass:UILabel.class]) { return; }
    UILabel *counter = (UILabel *)gesture.view;
    self.likes21 += 1;
    counter.text = [OCDemoWidgets likeText:self.likes21];
    [counter zl_setNeedsRichLabelLayout];
}

#pragma mark - 深色模式 / Dynamic Type

/// 22. 深色模式自动重新渲染 + 按系统文字大小缩放（adjustsFontForContentSizeCategory）
- (void)case22 {
    NSString *name = @"22. 深色模式 / Dynamic Type";
    NSString *source = @"Appearance: {mode}. Read the <h1>User Agreement</h1> <h2>NEW</h2>, "
                       @"text, tags and the badge follow dark mode and the system text size.";

    ZLTagRichLabel *label = [[ZLTagRichLabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.verticalAlignment = ZLLabelVerticalAlignmentTop;

    __weak typeof(self) weakSelf = self;
    __weak ZLTagRichLabel *weakLabel = label;
    [label updateTag:^(ZLTagRichLabel *v) {
        v.adjustsFontForContentSizeCategory = YES;
        // 动态颜色：深色 / 浅色切换后自动适配
        v.style = @{NSFontAttributeName: [UIFont systemFontOfSize:15],
                    NSForegroundColorAttributeName: UIColor.labelColor};
        v.tagStyle = @{NSForegroundColorAttributeName: OCDynamic(kBlue, OCHex(0x90CAF9)),
                       NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)};
        v.onTagTap = ^(ZLTagInfo *info) { [weakSelf onTap:name info:info action:nil]; };
        v.onParsed = ^(NSArray<ZLTagInfo *> *tags) { [weakSelf onParsed:name tags:tags]; };
        // 自定义 View：builder 在外观 / 字号变化时会重新执行，用 scaledFont: 让 View 字号一起变化
        v.tagWidgetBuilder = ^ZLRichWidget *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            ZLTagRichLabel *strongLabel = weakLabel;
            if (![info.name isEqualToString:@"h2"] || !strongLabel) { return nil; }
            OCPaddingLabel *badge = [[OCPaddingLabel alloc] initWithInsets:UIEdgeInsetsMake(1, 5, 1, 5)];
            badge.text = info.text;
            badge.font = [strongLabel scaledFont:[UIFont boldSystemFontOfSize:10]];
            badge.textColor = UIColor.whiteColor;
            badge.backgroundColor = OCDynamic(kDeepOrange, OCHex(0xFF8A65));
            badge.layer.cornerRadius = 4;
            badge.layer.masksToBounds = YES;
            return [[ZLRichWidget alloc] initWithView:badge
                                               size:CGSizeZero
                                           position:ZLRichWidgetPositionReplace
                                          alignment:ZLRichWidgetAlignmentMiddle
                                           tappable:YES];
        };
        // 规则 handler 也会重新执行：按当前外观返回不同内容
        [v addRuleWithName:@"mode" pattern:@"\\{mode\\}" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            BOOL dark = weakLabel.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
            [ctx setText:dark ? @"🌙 Dark" : @"☀️ Light"
              attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:15],
                           NSForegroundColorAttributeName: UIColor.secondaryLabelColor}];
        }];
        v.text = source;
    }];

    // 预览区域：外观 / 字号的覆盖只作用在这里，不影响整个页面
    UIView *preview = [[UIView alloc] init];
    preview.backgroundColor = UIColor.secondarySystemBackgroundColor;
    preview.layer.cornerRadius = 8;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [preview addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:preview.topAnchor constant:10],
        [label.bottomAnchor constraintEqualToAnchor:preview.bottomAnchor constant:-10],
        [label.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor constant:-10],
    ]];
    self.case22Preview = preview;
    self.case22Label = label;

    UISegmentedControl *appearance = [[UISegmentedControl alloc] initWithItems:@[@"跟随系统", @"浅色", @"深色"]];
    appearance.selectedSegmentIndex = 0;
    [appearance addTarget:self action:@selector(appearanceChanged22:) forControlEvents:UIControlEventValueChanged];

    UISegmentedControl *sizes = [[UISegmentedControl alloc] initWithItems:@[@"系统", @"XS", @"L", @"XXXL", @"AX3"]];
    sizes.selectedSegmentIndex = 0;
    [sizes addTarget:self action:@selector(sizeChanged22:) forControlEvents:UIControlEventValueChanged];
    UILabel *sizeHint = [[UILabel alloc] init];
    sizeHint.numberOfLines = 0;
    sizeHint.font = [UIFont systemFontOfSize:11];
    sizeHint.textColor = [UIColor colorWithWhite:0 alpha:0.45];
    if (@available(iOS 17.0, *)) {
        sizeHint.text = @"文字大小只覆盖预览区域；选「系统」则跟随 设置 › 显示与亮度 › 文字大小";
    } else {
        sizes.enabled = NO;
        sizeHint.text = @"iOS 17 以下请在 设置 › 显示与亮度 › 文字大小 中调整";
    }

    UISwitch *scaleSwitch = [[UISwitch alloc] init];
    scaleSwitch.on = YES;
    [scaleSwitch addTarget:self action:@selector(scaleSwitchChanged22:) forControlEvents:UIControlEventValueChanged];
    UILabel *switchTitle = [[UILabel alloc] init];
    switchTitle.text = @"adjustsFontForContentSizeCategory";
    switchTitle.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    UIStackView *switchRow = [[UIStackView alloc] initWithArrangedSubviews:@[switchTitle, scaleSwitch]];
    switchRow.alignment = UIStackViewAlignmentCenter;

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[appearance, sizes, sizeHint, switchRow, preview]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;

    OCDemoCard *card = [[OCDemoCard alloc] initWithTitle:name source:source content:content];
    self.cards[name] = card;
    [self.stackView addArrangedSubview:card];
}

- (void)appearanceChanged22:(UISegmentedControl *)sender {
    UIUserInterfaceStyle styles[] = {UIUserInterfaceStyleUnspecified, UIUserInterfaceStyleLight, UIUserInterfaceStyleDark};
    self.case22Preview.overrideUserInterfaceStyle = styles[sender.selectedSegmentIndex];
}

- (void)sizeChanged22:(UISegmentedControl *)sender {
    if (@available(iOS 17.0, *)) {
        UIView *preview = self.case22Preview;
        NSArray<UIContentSizeCategory> *categories = @[UIContentSizeCategoryExtraSmall, UIContentSizeCategoryLarge,
                                                       UIContentSizeCategoryExtraExtraExtraLarge,
                                                       UIContentSizeCategoryAccessibilityExtraLarge];
        if (sender.selectedSegmentIndex == 0) {
            [preview.traitOverrides removeTrait:UITraitPreferredContentSizeCategory.class];
        } else {
            preview.traitOverrides.preferredContentSizeCategory = categories[sender.selectedSegmentIndex - 1];
        }
    }
}

- (void)scaleSwitchChanged22:(UISwitch *)sender {
    self.case22Label.adjustsFontForContentSizeCategory = sender.isOn;
}

#pragma mark - 通用标签

/// 27. 通用标签：任意标签名、标签属性、嵌套、自闭合
- (void)case27 {
    NSString *name = @"27. 通用标签（任意标签名 / 属性 / 嵌套）";
    NSString *source = @"支持 <b>粗体</b>、<i>斜体</i>、<u>下划线</u>、<color value=\"#E91E63\">任意颜色</color>、"
        @"<size value=\"20\">字号</size>。可以嵌套：<b>粗体里 <color value=\"#2196F3\">蓝色 <u>加下划线</u></color></b>。"
        @"链接 <a href=\"https://github.com\">GitHub</a>，图标 <icon name=\"star.fill\" color=\"orange\"/>，"
        @"换行<br/>容错：<b>未闭合的 <i>标签</b> 原样显示，多余的 </u> 也原样显示。";

    __weak typeof(self) weakSelf = self;
    [self addCase:name source:source configure:^(ZLTagRichLabel *v) {
        // 识别任意标签名，支持嵌套和自闭合（默认只识别 <h> / <hN>）
        v.tagNamePattern = ZLTagParser.anyTagNamePattern;
        v.allowsNestedTags = YES;
        v.allowsSelfClosingTags = YES;
        v.tagStyles = @{
            @"b": @{NSFontAttributeName: [UIFont boldSystemFontOfSize:15]},
            @"i": @{NSFontAttributeName: [UIFont italicSystemFontOfSize:15]},
            @"u": @{NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)},
            @"a": @{NSForegroundColorAttributeName: kBlue, NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)},
        };
        // 按属性设置样式：<color value="…">、<size value="…">
        v.tagStyleBuilder = ^NSDictionary<NSAttributedStringKey, id> *(ZLTagInfo *info) {
            NSMutableDictionary *style = [NSMutableDictionary dictionary];
            UIColor *color = [info.name isEqualToString:@"color"] ? [info colorAttributeNamed:@"value"] : nil;
            if (color) style[NSForegroundColorAttributeName] = color;
            NSString *size = [info.name isEqualToString:@"size"] ? [info attributeNamed:@"value"] : nil;
            if (size.doubleValue > 0) style[NSFontAttributeName] = [UIFont systemFontOfSize:size.doubleValue];
            return style;
        };
        // 自闭合标签：<br/> 换行
        v.tagSpanBuilder = ^NSAttributedString *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            return [info.name isEqualToString:@"br"] ? [[NSAttributedString alloc] initWithString:@"\n" attributes:style] : nil;
        };
        // 自闭合标签：<icon name="…" color="…"/> 显示 SF Symbol
        v.tagWidgetBuilder = ^ZLRichWidget *(ZLTagInfo *info, NSDictionary<NSAttributedStringKey, id> *style) {
            NSString *symbol = [info attributeNamed:@"name"];
            if (![info.name isEqualToString:@"icon"] || symbol == nil) return nil;
            UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
            icon.tintColor = [info colorAttributeNamed:@"color"] ?: kGrey;
            icon.contentMode = UIViewContentModeScaleAspectFit;
            return [ZLRichWidget widgetWithView:icon size:CGSizeMake(16, 16) position:ZLRichWidgetPositionReplace];
        };
        // <a> 读取 href；其他标签走 onTagTap（内层标签优先响应点击）
        [v setTapHandler:^(ZLTagInfo *info) {
            [weakSelf onTap:name info:info
                     action:[NSString stringWithFormat:@"打开 %@", [info attributeNamed:@"href"] ?: @""]];
        } forTag:@"a"];
        v.onTagTap = ^(ZLTagInfo *info) {
            NSMutableArray<NSString *> *path = [NSMutableArray array];
            for (ZLTagInfo *t = info; t != nil; t = t.parent) {
                [path insertObject:[NSString stringWithFormat:@"<%@>", t.name] atIndex:0];
            }
            [weakSelf onTap:name info:info
                     action:[@"onTagTap  " stringByAppendingString:[path componentsJoinedByString:@" › "]]];
        };
        v.tagHighlightStyles = @{@"br": @{}, @"icon": @{}};
    }];
}

#pragma mark - 胶囊背景 / 渐变文字

/// 28. 胶囊背景（圆角背景 / 边框 / 内边距）与渐变文字，由 label 自己绘制
/// 28b. 从右到左（阿拉伯语 / 希伯来语）与双向混排下的胶囊：两侧内边距按视觉位置预留
- (void)case28b {
    NSString *name = @"28b. RTL / 双向混排的胶囊";
    NSString *source = @"مرحبا #سويفت# لغة برمجة قوية\n"
                        @"שלום #סוויפט# היא שפה\n"
                        @"كبسولتان متجاورتان: #iOS##سويفت# معا\n"
                        @"تعلم #SwiftUI# اليوم\n"
                        @"Learn #سويفت# today";
    __weak typeof(self) weakSelf = self;
    [self addRuleCase:name source:source configure:^(ZLRichLabel *v) {
        NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
        paragraph.lineSpacing = 8;
        NSMutableDictionary *style = [v.style mutableCopy];
        style[NSParagraphStyleAttributeName] = paragraph;
        v.style = style;
        [v addRuleWithName:@"topic" pattern:@"#[^#\\s]+#" options:0 priority:0 error:nil handler:^(ZLRichRuleContext *ctx) {
            [ctx addAttributes:@{NSForegroundColorAttributeName: kPurple,
                                 ZLRichLabel.textBackgroundAttributeName: [ZLTextBackground capsule:kPurple]}];
            ctx.highlightStyle = @{ZLRichLabel.textBackgroundAttributeName:
                                       [ZLTextBackground backgroundWithFillColor:[kPurple colorWithAlphaComponent:0.3]
                                                                     strokeColor:nil cornerRadius:-1]};
            ctx.onTap = [weakSelf ruleTapForCase:name action:@"点击 RTL 胶囊"];
        }];
    }];
}

- (void)case28 {
    NSString *name = @"28. 胶囊背景 / 渐变文字";
    NSString *source = @"<grad>Swift 富文本</grad> <new>NEW</new>\n"
        @"话题：#iOS开发# #SwiftUI##UIKit# 点击胶囊有按下效果。"
        @"行内代码 `label.text = value` 和 `rebuild()`。"
        @"<tag>只有边框</tag> <tag>Tag</tag> "
        @"<rainbow>竖向渐变 + 跨行的长胶囊也能正确绘制，每一行单独一段</rainbow>，"
        @"<pill>很长的胶囊文字在折行时会分成两段分别绘制</pill>。";

    __weak typeof(self) weakSelf = self;
    [self addCase:name source:source configure:^(ZLTagRichLabel *v) {
        NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
        paragraph.lineSpacing = 6;   // 胶囊的垂直内边距不占行高，加一点行距避免上下行重叠
        NSMutableDictionary *style = [OCDemoViewController.baseStyle mutableCopy];
        style[NSParagraphStyleAttributeName] = paragraph;
        v.style = style;
        v.tagNamePattern = ZLTagParser.anyTagNamePattern;
        v.allowsNestedTags = YES;

        ZLTextBackground *badge = [ZLTextBackground backgroundWithFillColor:kDeepOrange strokeColor:nil cornerRadius:4];
        badge.padding = UIEdgeInsetsMake(2, 4, 2, 4);
        ZLTextBackground *outline = [ZLTextBackground backgroundWithFillColor:nil strokeColor:kTeal cornerRadius:-1];
        ZLTextGradient *vertical = [ZLTextGradient gradientWithColors:@[kBlue, kGreen]];
        vertical.startPoint = CGPointMake(0.5, 0);
        vertical.endPoint = CGPointMake(0.5, 1);

        v.tagStyles = @{
            // 渐变标题
            @"grad": @{NSFontAttributeName: [UIFont boldSystemFontOfSize:22],
                       ZLRichLabel.textGradientAttributeName: [ZLTextGradient gradientWithColors:@[kPink, kOrange, kDeepPurple]]},
            // 实心小徽章
            @"new": @{NSFontAttributeName: [UIFont boldSystemFontOfSize:11],
                      NSForegroundColorAttributeName: UIColor.whiteColor,
                      NSBaselineOffsetAttributeName: @3,
                      ZLRichLabel.textBackgroundAttributeName: badge},
            // 只有边框
            @"tag": @{NSForegroundColorAttributeName: kTeal, NSFontAttributeName: [UIFont systemFontOfSize:13],
                      ZLRichLabel.textBackgroundAttributeName: outline},
            // 竖向渐变
            @"rainbow": @{NSFontAttributeName: [UIFont boldSystemFontOfSize:15],
                          ZLRichLabel.textGradientAttributeName: vertical},
            // 跨行的胶囊
            @"pill": @{NSForegroundColorAttributeName: kIndigo,
                       ZLRichLabel.textBackgroundAttributeName: [ZLTextBackground capsule:kIndigo]},
        };
        // 按下高亮：换成更深的胶囊
        v.tagHighlightStyles = @{
            @"tag": @{ZLRichLabel.textBackgroundAttributeName:
                          [ZLTextBackground backgroundWithFillColor:[kTeal colorWithAlphaComponent:0.15]
                                                        strokeColor:kTeal cornerRadius:-1]},
            @"pill": @{ZLRichLabel.textBackgroundAttributeName:
                           [ZLTextBackground backgroundWithFillColor:[kIndigo colorWithAlphaComponent:0.3]
                                                         strokeColor:nil cornerRadius:-1]},
        };
        // #话题#：胶囊 + 点击
        [v addRuleWithName:@"topic" pattern:@"#[^#\\s]+#" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx addAttributes:@{NSForegroundColorAttributeName: kPurple,
                                 ZLRichLabel.textBackgroundAttributeName: [ZLTextBackground capsule:kPurple]}];
            ctx.highlightStyle = @{ZLRichLabel.textBackgroundAttributeName:
                                       [ZLTextBackground backgroundWithFillColor:[kPurple colorWithAlphaComponent:0.3]
                                                                     strokeColor:nil cornerRadius:-1]};
            ctx.onTap = [weakSelf ruleTapForCase:name action:@"点击话题"];
        }];
        // `代码`：去掉反引号，等宽字体 + 灰色背景 + 细边框
        [v addRuleWithName:@"code" pattern:@"`([^`]+)`" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx setText:[ctx groupAtIndex:1] ?: @"" attributes:@{
                NSFontAttributeName: [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular],
                NSForegroundColorAttributeName: kDeepOrange,
                ZLRichLabel.textBackgroundAttributeName: ZLTextBackground.code,
            }];
        }];
    }];
}

#pragma mark - 选中复制

/// 26. 选中复制：长按选词、拖动 / 拖柄调整范围，菜单「复制 / 复制原文 / 全选」
- (void)case26 {
    NSString *name = @"26. 选中复制（isSelectable）";
    NSString *source = @"长按选中一个词，拖动手指或两端的拖柄调整范围 [smile]，松手弹出菜单："
                       @"「复制」得到展示文字，「复制原文」得到 @alice 和 [smile] 的原始写法。"
                       @"点击 <h1>用户协议</h1> 仍然可以跳转，点击文字取消选中。";

    ZLTagRichLabel *label = [[ZLTagRichLabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.verticalAlignment = ZLLabelVerticalAlignmentTop;
    UILabel *status = [[UILabel alloc] init];
    status.numberOfLines = 0;
    status.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    status.textColor = [UIColor colorWithWhite:0 alpha:0.6];
    status.text = @"长按文字开始选中";

    __weak typeof(self) weakSelf = self;
    __weak ZLTagRichLabel *weakLabel = label;
    __weak UILabel *weakStatus = status;
    [label updateTag:^(ZLTagRichLabel *v) {
        v.style = OCDemoViewController.baseStyle;
        v.isSelectable = YES;
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.onTagTap = ^(ZLTagInfo *info) { [weakSelf onTap:name info:info action:nil]; };
        // 表情：选中后「复制」得到空（图片），「复制原文」得到 [smile]
        [v addRuleWithName:@"emoji" pattern:@"\\[smile\\]" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.image = [[UIImage systemImageNamed:@"face.smiling"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            attachment.bounds = CGRectMake(0, 0, 17, 17);
            NSMutableAttributedString *content = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
            [content addAttributes:@{NSForegroundColorAttributeName: kOrange} range:NSMakeRange(0, content.length)];
            [ctx.attributedString setAttributedString:content];
        }];
        // @提及：展示为 👤alice，原文为 @alice（长按命中时整体选中）
        [v addRuleWithName:@"mention" pattern:@"@\\w+" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx setText:[@"👤" stringByAppendingString:[ctx.matchedText substringFromIndex:1]]
              attributes:@{NSForegroundColorAttributeName: kPurple}];
        }];
        v.onSelectionChanged = ^(NSRange range) {
            ZLTagRichLabel *strongLabel = weakLabel;
            if (!strongLabel) { return; }
            weakStatus.text = range.location == NSNotFound ? @"未选中" : [NSString stringWithFormat:
                @"selectedRange   = {%lu, %lu}\nselectedText    = \"%@\"\nselectedRawText = \"%@\"",
                (unsigned long)range.location, (unsigned long)range.length,
                strongLabel.selectedText ?: @"", strongLabel.selectedRawText ?: @""];
        };
        v.onCopy = ^(NSString *text, BOOL isRaw) {
            ZLTagInfo *info = [[ZLTagInfo alloc] initWithIndex:0 name:isRaw ? @"copy-raw" : @"copy" text:text raw:@""];
            [weakSelf onTap:name info:info action:isRaw ? @"onCopy → 复制原文" : @"onCopy → 复制展示文字"];
        };
        v.text = source;
    }];

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[label, status]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;
    OCDemoCard *card = [[OCDemoCard alloc] initWithTitle:name source:source content:content];
    self.cards[name] = card;
    [self.stackView addArrangedSubview:card];
}

#pragma mark - 长按 / 双击 / 扩大点击热区

/// 25. 长按菜单（复制 / 举报）、按命中区分的长按、双击、扩大点击热区
- (void)case25 {
    NSString *name = @"25. 长按菜单 / 双击 / 扩大点击热区";
    NSString *source = @"Long press blank text to copy or report. Long press <h1>User Agreement</h1> or @alice "
                       @"for their own menus, double tap to like ❤️. Tap slightly below @bob: extendsLinkTouchArea "
                       @"expands the touch area by up to 15pt.";
    __weak typeof(self) weakSelf = self;
    self.case25Label = [self addCase:name source:source configure:^(ZLTagRichLabel *v) {
        NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
        paragraph.lineSpacing = 10;
        NSMutableDictionary *style = [OCDemoViewController.baseStyle mutableCopy];
        style[NSParagraphStyleAttributeName] = paragraph;
        v.style = style;
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        v.tagHighlightStyle = @{NSBackgroundColorAttributeName: [UIColor colorWithWhite:0 alpha:0.08]};
        v.extendsLinkTouchArea = YES;

        // 规则命中自己的长按：只回调它，不再回调 onLongPress
        [v addRuleWithName:@"mention" pattern:@"@\\w+" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx addAttributes:@{NSForegroundColorAttributeName: kPurple,
                                 NSFontAttributeName: [UIFont boldSystemFontOfSize:15]}];
            ctx.onTap = ^(ZLRichMatch *match) {
                [weakSelf onTap:name info:[OCDemoViewController infoForMatch:match]
                         action:[NSString stringWithFormat:@"mention onTap → 打开 %@ 的主页", match.text]];
            };
            ctx.onLongPress = ^(ZLRichMatch *match) {
                NSString *user = match.text;
                ZLTagInfo *info = [OCDemoViewController infoForMatch:match];
                [weakSelf showMenu25:user items:@[
                    @[[NSString stringWithFormat:@"复制 %@", user], ^{ [weakSelf copy25:user caseName:name info:info]; }],
                    @[[NSString stringWithFormat:@"举报 %@", user], ^{
                        [weakSelf onTap:name info:info action:[NSString stringWithFormat:@"ctx.onLongPress → 举报 %@", user]];
                    }],
                ]];
            };
        }];
        // 标签的长按
        v.onTagLongPress = ^(ZLTagInfo *info) {
            [weakSelf showMenu25:[NSString stringWithFormat:@"<%@> %@", info.name, info.text] items:@[
                @[[NSString stringWithFormat:@"复制「%@」", info.text], ^{ [weakSelf copy25:info.text caseName:name info:info]; }],
            ]];
        };
        // 其他位置的长按：复制原文 / 展示文字、举报
        v.onLongPress = ^(ZLRichGestureInfo *gesture) {
            ZLTagInfo *info = [[ZLTagInfo alloc] initWithIndex:gesture.characterIndex name:@"long-press"
                                                        text:gesture.displayText raw:gesture.rawText];
            [weakSelf showMenu25:[NSString stringWithFormat:@"长按位置字符下标：%ld", (long)gesture.characterIndex] items:@[
                @[@"复制原文（rawText）", ^{ [weakSelf copy25:gesture.rawText caseName:name info:info]; }],
                @[@"复制展示文字（displayText）", ^{ [weakSelf copy25:gesture.displayText caseName:name info:info]; }],
                @[@"举报", ^{ [weakSelf onTap:name info:info action:@"onLongPress → 举报"]; }],
            ]];
        };
        // 双击：设置后单击链接会等双击判定失败才触发（约 0.3 秒）
        v.onDoubleTap = ^(ZLRichGestureInfo *gesture) {
            OCDemoViewController *strongSelf = weakSelf;
            ZLTagRichLabel *label = strongSelf.case25Label;
            if (!strongSelf || !label) { return; }
            ZLTagInfo *info = [[ZLTagInfo alloc] initWithIndex:gesture.characterIndex name:@"double-tap"
                                                        text:gesture.matchDisplayText ?: @"" raw:gesture.match.text ?: @""];
            [strongSelf onTap:name info:info action:[NSString stringWithFormat:@"onDoubleTap → 点赞 ❤️（位置 %d, %d）",
                                                     (int)gesture.location.x, (int)gesture.location.y]];
            [strongSelf showHeart25In:label at:gesture.location];
        };
    }];
}

/// 在长按位置弹出菜单（iPad 上以 popover 显示）。items：@[@[标题, block], ...]
- (void)showMenu25:(NSString *)title items:(NSArray<NSArray *> *)items {
    ZLTagRichLabel *label = self.case25Label;
    if (!label) { return; }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSArray *item in items) {
        void (^action)(void) = item[1];
        [sheet addAction:[UIAlertAction actionWithTitle:item[0] style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { action(); }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    CGPoint location = [label.richLongPressGesture locationInView:label];
    sheet.popoverPresentationController.sourceView = label;
    sheet.popoverPresentationController.sourceRect = CGRectMake(location.x, location.y, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)copy25:(NSString *)text caseName:(NSString *)caseName info:(ZLTagInfo *)info {
    UIPasteboard.generalPasteboard.string = text;
    NSString *shown = text.length > 40 ? [[text substringToIndex:40] stringByAppendingString:@"…"] : text;
    [self onTap:caseName info:info action:[NSString stringWithFormat:@"已复制：%@", shown]];
}

- (void)showHeart25In:(UIView *)label at:(CGPoint)point {
    UILabel *heart = [[UILabel alloc] init];
    heart.text = @"❤️";
    heart.font = [UIFont systemFontOfSize:28];
    [heart sizeToFit];
    heart.center = point;
    [label addSubview:heart];
    [UIView animateWithDuration:0.6 animations:^{
        heart.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(1.6, 1.6), 0, -12);
        heart.alpha = 0;
    } completion:^(BOOL finished) { [heart removeFromSuperview]; }];
}

#pragma mark - 展开 / 收起

/// 24. 展开 / 收起：超过 numberOfLines 行时末尾显示可点击的「… 全文」，展开后末尾显示「收起」
- (void)case24 {
    NSString *longText = @"<h1>ZLRichLabel</h1> 支持「展开 / 收起」：内容超过 numberOfLines 行时，最后一行末尾显示可点击的「… 全文」，"
                         @"点击后展开全部内容，末尾出现「收起」。适用于动态、评论、商品详情等场景。"
                         @"展开状态可以保存在数据里，列表复用 cell 时直接设置 isExpanded，不会触发 onExpandChanged。"
                         @"<h2>#标签#</h2> 的点击和按下高亮不受影响。";
    NSArray<NSArray<NSString *> *> *cases = @[
        @[@"24. 展开 / 收起（收起时 3 行）", longText],
        @[@"24b. 内容不足 3 行：不显示「全文」", @"<h1>短内容</h1> 不会被截断，也不显示按钮。"],
    ];
    __weak typeof(self) weakSelf = self;
    for (NSArray<NSString *> *item in cases) {
        NSString *title = item[0];
        [self addCase:title source:item[1] configure:^(ZLTagRichLabel *v) {
            v.numberOfLines = 3;
            v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
            v.tagHighlightStyle = @{NSBackgroundColorAttributeName: [UIColor colorWithWhite:0 alpha:0.08]};
            NSDictionary *tokenStyle = @{NSForegroundColorAttributeName: kDeepOrange,
                                         NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]};
            v.expandToken = [[NSAttributedString alloc] initWithString:@"… 全文" attributes:tokenStyle];
            v.collapseToken = [[NSAttributedString alloc] initWithString:@" 收起" attributes:tokenStyle];
            v.onExpandChanged = ^(BOOL expanded) {
                OCDemoViewController *strongSelf = weakSelf;
                if (!strongSelf) { return; }
                ZLTagInfo *info = [[ZLTagInfo alloc] initWithIndex:0 name:@"expand" text:expanded ? @"全文" : @"收起" raw:@""];
                [strongSelf onTap:title info:info action:[NSString stringWithFormat:@"onExpandChanged(%@)", expanded ? @"YES" : @"NO"]];
                [UIView animateWithDuration:0.25 animations:^{ [strongSelf.view layoutIfNeeded]; }];
            };
        }];
    }

    // 24e. 外部决定是否展开 / 收起：设置 onExpandTokenTap 后点击按钮不再自动切换
    NSString *externalTitle = @"24e. onExpandTokenTap：外部决定是否展开 / 收起";
    [self addCase:externalTitle source:longText configure:^(ZLTagRichLabel *v) {
        v.numberOfLines = 3;
        v.tagStyle = @{NSForegroundColorAttributeName: kBlue};
        NSDictionary *tokenStyle = @{NSForegroundColorAttributeName: [UIColor systemTealColor],
                                     NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]};
        v.expandToken = [[NSAttributedString alloc] initWithString:@"… 全文" attributes:tokenStyle];
        v.collapseToken = [[NSAttributedString alloc] initWithString:@" 收起" attributes:tokenStyle];
        v.onExpandChanged = ^(BOOL expanded) {
            OCDemoViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            ZLTagInfo *info = [[ZLTagInfo alloc] initWithIndex:0 name:@"expand" text:expanded ? @"全文" : @"收起" raw:@""];
            [strongSelf onTap:externalTitle info:info action:[NSString stringWithFormat:@"onExpandChanged(%@)", expanded ? @"YES" : @"NO"]];
            [UIView animateWithDuration:0.25 animations:^{ [strongSelf.view layoutIfNeeded]; }];
        };
        v.onExpandTokenTap = ^(ZLRichLabel *label, BOOL wantsExpand) {
            OCDemoViewController *strongSelf = weakSelf;
            if (!strongSelf) { return; }
            ZLTagInfo *info = [[ZLTagInfo alloc] initWithIndex:0 name:@"expandToken" text:wantsExpand ? @"全文" : @"收起" raw:@""];
            [strongSelf onTap:externalTitle info:info
                       action:[NSString stringWithFormat:@"onExpandTokenTap(wantsExpand: %@)", wantsExpand ? @"YES" : @"NO"]];
            UIAlertController *sheet = [UIAlertController alertControllerWithTitle:wantsExpand ? @"展开全文？" : @"收起？"
                                                                           message:@"设置了 onExpandTokenTap：由外部决定，不设置时内部自动切换"
                                                                    preferredStyle:UIAlertControllerStyleActionSheet];
            __weak ZLRichLabel *weakLabel = label;
            [sheet addAction:[UIAlertAction actionWithTitle:wantsExpand ? @"展开（toggleExpanded）" : @"收起（toggleExpanded）"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *action) { [weakLabel toggleExpanded]; }]];
            if (wantsExpand) {
                [sheet addAction:[UIAlertAction actionWithTitle:@"跳转详情页（不展开）" style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
                    [weakSelf onTap:externalTitle info:info action:@"跳转详情页"];
                }]];
            }
            [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            sheet.popoverPresentationController.sourceView = label;
            sheet.popoverPresentationController.sourceRect = label.expandTokenRect;
            [strongSelf presentViewController:sheet animated:YES completion:nil];
        };
    }];
}

#pragma mark - 性能

/// 23. 性能：命中的渲染结果按命中缓存、排版结果按「文本 + 宽度」缓存
- (void)case23 {
    NSString *name = @"23. 性能：渲染缓存 / 排版缓存";
    NSInteger count = 200;
    NSMutableString *source = [NSMutableString string];
    for (NSInteger i = 0; i < count; i++) {
        [source appendFormat:@"@user%ld [smile] #topic%ld# ", (long)i, (long)(i % 10)];
    }
    NSString *shownSource = [NSString stringWithFormat:
        @"@user0 [smile] #topic0# @user1 [smile] #topic1# …（重复 %ld 次，共 %ld 个命中）", (long)count, (long)count * 3];

    ZLRichLabel *label = [[ZLRichLabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 4;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.verticalAlignment = ZLLabelVerticalAlignmentTop;
    self.case23Label = label;

    __weak typeof(self) weakSelf = self;
    [label update:^(ZLRichLabel *v) {
        v.style = OCDemoViewController.baseStyle;
        v.highlightStyle = @{NSBackgroundColorAttributeName: [kAmber colorWithAlphaComponent:0.4]};
        [v addRuleWithName:@"mention" pattern:@"@\\w+" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            BOOL green = weakSelf.mentionGreen23;
            [ctx addAttributes:@{NSForegroundColorAttributeName: green ? kGreen : kPurple}];
            ctx.onTap = [weakSelf ruleTapForCase:name action:@"rule onTap"];
        }];
        [v addRuleWithName:@"emoji" pattern:@"\\[smile\\]" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.image = [[UIImage systemImageNamed:@"face.smiling"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            attachment.bounds = CGRectMake(0, 0, 16, 16);
            [ctx.attributedString setAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
            [ctx addAttributes:@{NSForegroundColorAttributeName: kOrange}];
        }];
        [v addRuleWithName:@"topic" pattern:@"#\\w+#" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            [ctx addAttributes:@{NSForegroundColorAttributeName: kBlue}];
        }];
    }];

    UILabel *stats = [[UILabel alloc] init];
    stats.numberOfLines = 0;
    stats.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    stats.textColor = [UIColor colorWithWhite:0 alpha:0.7];
    self.case23Stats = stats;

    NSArray<NSArray *> *buttons = @[
        @[@"改按下高亮", NSStringFromSelector(@selector(highlight23))],
        @[@"末尾追加文字", NSStringFromSelector(@selector(append23))],
        @[@"只刷新 @提及", NSStringFromSelector(@selector(recolorMentions23))],
        @[@"rebuild()", NSStringFromSelector(@selector(rebuild23))],
        @[@"sizeThatFits ×100", NSStringFromSelector(@selector(measureSize23))],
        @[@"解析 1.5 万命中", NSStringFromSelector(@selector(parse23))],
    ];
    NSMutableArray<UIView *> *arranged = [NSMutableArray arrayWithObject:label];
    for (NSUInteger start = 0; start < buttons.count; start += 3) {
        UIStackView *row = [[UIStackView alloc] init];
        row.distribution = UIStackViewDistributionFillEqually;
        row.spacing = 6;
        for (NSUInteger i = start; i < MIN(start + 3, buttons.count); i++) {
            UIButtonConfiguration *config = [UIButtonConfiguration tintedButtonConfiguration];
            config.title = buttons[i][0];
            config.buttonSize = UIButtonConfigurationSizeMini;
            UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
            button.titleLabel.adjustsFontSizeToFitWidth = YES;
            [button addTarget:self action:NSSelectorFromString(buttons[i][1]) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:button];
        }
        [arranged addObject:row];
    }
    [arranged addObject:stats];

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:arranged];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;

    OCDemoCard *card = [[OCDemoCard alloc] initWithTitle:name source:shownSource content:content];
    self.cards[name] = card;
    [self.stackView addArrangedSubview:card];

    [self measure23:@"首次渲染" block:^{ label.text = source; }];
}

/// 执行操作并展示耗时与缓存统计
- (void)measure23:(NSString *)title block:(void (^)(void))block {
    ZLRichLabel *label = self.case23Label;
    if (!label) { return; }
    [label.statistics reset];
    CFTimeInterval start = CACurrentMediaTime();
    block();
    [label.superview layoutIfNeeded];
    double ms = (CACurrentMediaTime() - start) * 1000;
    ZLRichLabelStatistics *s = label.statistics;
    NSInteger imageViews = 0;
    for (UIView *view in label.subviews) { if ([view isKindOfClass:UIImageView.class]) { imageViews++; } }
    self.case23Stats.text = [NSString stringWithFormat:
        @"%@：%.2f ms\nhandler 执行 %ld 次，复用 %ld 个命中\n渲染 %ld 次，创建 framesetter %ld 次，尺寸缓存命中 %ld 次\n当前命中 %lu 个，自定义 View %ld 个",
        title, ms, (long)s.handlerCalls, (long)s.reusedMatches, (long)s.renders, (long)s.framesetterCreations,
        (long)s.sizeCacheHits, (unsigned long)label.matches.count, (long)imageViews];
}

/// 按下高亮不影响 handler 输出：全部复用
- (void)highlight23 {
    self.highlightBlue23 = !self.highlightBlue23;
    UIColor *color = self.highlightBlue23 ? kBlue : kAmber;
    ZLRichLabel *label = self.case23Label;
    [self measure23:@"改按下高亮" block:^{
        label.highlightStyle = @{NSBackgroundColorAttributeName: [color colorWithAlphaComponent:0.4]};
    }];
}

/// 末尾追加：前面命中的位置和内容都没变，只渲染新增的命中
- (void)append23 {
    self.appended23 += 1;
    NSInteger n = self.appended23;
    ZLRichLabel *label = self.case23Label;
    [self measure23:[NSString stringWithFormat:@"末尾追加 @new%ld", (long)n] block:^{
        label.text = [label.rawText stringByAppendingFormat:@"@new%ld ", (long)n];
    }];
}

/// handler 依赖的外部数据变了，只作废这条规则：表情图片和话题直接复用
- (void)recolorMentions23 {
    self.mentionGreen23 = !self.mentionGreen23;
    ZLRichLabel *label = self.case23Label;
    [self measure23:@"只刷新 @提及（setNeedsRebuildForRuleNamed:）" block:^{
        [label setNeedsRebuildForRuleNamed:@"mention"];
    }];
}

/// 强制全部重新执行（对比用）
- (void)rebuild23 {
    ZLRichLabel *label = self.case23Label;
    [self measure23:@"rebuild 全部重新执行" block:^{ [label rebuild]; }];
}

/// 同一宽度重复计算尺寸：只有第一次真正排版
- (void)measureSize23 {
    ZLRichLabel *label = self.case23Label;
    [self measure23:@"sizeThatFits ×100" block:^{
        CGSize fitting = CGSizeMake(CGRectGetWidth(label.bounds), CGFLOAT_MAX);
        for (NSInteger i = 0; i < 100; i++) { (void)[label sizeThatFits:fitting]; }
    }];
}

/// 解析器：1.5 万个命中按优先级去重（原来 O(n²)，现在二分查找 O(n log n)）
- (void)parse23 {
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = 0; i < 5000; i++) { [text appendString:@"@user #tag# word "]; }
    void (^noop)(ZLRichRuleContext *) = ^(ZLRichRuleContext *ctx) {};
    NSArray<ZLRichRule *> *rules = @[
        [[ZLRichRule alloc] initWithName:@"mention" pattern:@"@\\w+" options:0 priority:0 error:nil handler:noop],
        [[ZLRichRule alloc] initWithName:@"topic" pattern:@"#\\w+#" options:0 priority:0 error:nil handler:noop],
        [[ZLRichRule alloc] initWithName:@"word" pattern:@"\\w+" options:0 priority:-1 error:nil handler:noop],
    ];
    CFTimeInterval start = CACurrentMediaTime();
    NSArray<ZLRichMatch *> *matches = [ZLRichParser matchesInString:text rules:rules];
    double ms = (CACurrentMediaTime() - start) * 1000;
    self.case23Stats.text = [NSString stringWithFormat:
        @"ZLRichParser.resolve：%.2f ms\n文本 %lu 字符，3 条规则，生效命中 %lu 个\n（含正则匹配耗时；label 未参与）",
        ms, (unsigned long)text.length, (unsigned long)matches.count];
}

#pragma mark - 首 / 中 / 尾自定义 View 跟随 label 尺寸

/// 30. 开头 / 中间 / 结尾插入自定义 View，修改 label 宽度、对齐、行数、内边距后，View 自动跟随文字重新定位。
/// 下方实时比较每个 View 的 frame 与它在文字中占位符的位置（boundingRectForCharacterRange:）
- (void)case30 {
    NSString *name = @"30. 首 / 中 / 尾自定义 View 跟随 label 尺寸";
    NSString *source = @"[avatar] 开头是头像 View，中间插入一个 [follow] 按钮和 [badge] 徽章，"
                        @"拖动下面的宽度滑块，后面的文字会重新折行，View 跟着文字一起移动，结尾是箭头 [arrow]";

    UILabel *avatar = [UILabel new];
    avatar.text = @"Z";
    avatar.font = [UIFont boldSystemFontOfSize:12];
    avatar.textColor = UIColor.whiteColor;
    avatar.textAlignment = NSTextAlignmentCenter;
    avatar.backgroundColor = kDeepPurple;
    avatar.layer.cornerRadius = 11;
    avatar.layer.masksToBounds = YES;

    // 自己处理点击的按钮：文字变化后尺寸变化，调用 zl_setNeedsRichLabelLayout 重新排版
    OCPaddingLabel *follow = [[OCPaddingLabel alloc] initWithInsets:UIEdgeInsetsMake(2, 8, 2, 8)];
    follow.text = @"+ 关注";
    follow.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    follow.textColor = UIColor.whiteColor;
    follow.backgroundColor = kBlue;
    follow.layer.cornerRadius = 9;
    follow.layer.masksToBounds = YES;
    follow.userInteractionEnabled = YES;
    [follow addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(follow30:)]];

    OCPaddingLabel *badge = [[OCPaddingLabel alloc] initWithInsets:UIEdgeInsetsMake(1, 5, 1, 5)];
    badge.text = @"LV.5";
    badge.font = [UIFont boldSystemFontOfSize:10];
    badge.textColor = UIColor.whiteColor;
    badge.backgroundColor = kAmber;
    badge.layer.cornerRadius = 4;
    badge.layer.masksToBounds = YES;

    UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right.circle.fill"]];
    arrow.tintColor = kTeal;

    self.case30Views = @[@[@"头像", avatar], @[@"按钮", follow], @[@"徽章", badge], @[@"箭头", arrow]];
    NSDictionary<NSString *, ZLRichWidget *> *widgets = @{
        @"avatar": [ZLRichWidget widgetWithView:avatar size:CGSizeMake(22, 22) position:ZLRichWidgetPositionReplace],
        // CGSizeZero：自动计算尺寸；按钮自己处理点击
        @"follow": [[ZLRichWidget alloc] initWithView:follow size:CGSizeZero position:ZLRichWidgetPositionReplace
                                            alignment:ZLRichWidgetAlignmentMiddle tappable:NO],
        @"badge": [ZLRichWidget widgetWithView:badge size:CGSizeZero position:ZLRichWidgetPositionReplace],
        @"arrow": [ZLRichWidget widgetWithView:arrow size:CGSizeMake(18, 18) position:ZLRichWidgetPositionReplace],
    };

    __weak typeof(self) weakSelf = self;
    ZLRichLabel *label = [[ZLRichLabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.verticalAlignment = ZLLabelVerticalAlignmentTop;
    label.backgroundColor = OCHex(0xEADDFF);
    [label update:^(ZLRichLabel *v) {
        v.style = OCDemoViewController.baseStyle;
        [v addRuleWithName:@"view" pattern:@"\\[(\\w+)\\]" options:0 priority:0 error:nil
                   handler:^(ZLRichRuleContext *ctx) {
            NSString *key = [ctx groupAtIndex:1];
            ZLRichWidget *widget = key ? widgets[key] : nil;
            if (!widget) return;
            [ctx.attributedString setAttributedString:[ctx attachmentStringForWidget:widget style:nil]];
            ctx.onTap = [weakSelf ruleTapForCase:name action:[@"点击 View " stringByAppendingString:key]];
        }];
        v.text = source;
    }];
    self.case30Label = label;

    // label 放在容器里，宽度 = 容器宽度 × 滑块比例（Auto Layout 自适应高度）
    UIView *container = [UIView new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    NSLayoutConstraint *width = [label.widthAnchor constraintEqualToAnchor:container.widthAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:container.topAnchor],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        width,
    ]];
    self.case30Width = width;

    UISlider *slider = [UISlider new];
    slider.minimumValue = 0.3;
    slider.maximumValue = 1;
    slider.value = 1;
    [slider addTarget:self action:@selector(width30:) forControlEvents:UIControlEventValueChanged];
    self.case30Slider = slider;

    UISegmentedControl *alignment = [[UISegmentedControl alloc] initWithItems:@[@"自然", @"左", @"居中", @"右"]];
    alignment.selectedSegmentIndex = 0;
    [alignment addTarget:self action:@selector(alignment30:) forControlEvents:UIControlEventValueChanged];

    UISegmentedControl *lines = [[UISegmentedControl alloc] initWithItems:@[@"不限行", @"2 行", @"内边距 0", @"内边距 16"]];
    lines.selectedSegmentIndex = UISegmentedControlNoSegment;
    [lines addTarget:self action:@selector(lines30:) forControlEvents:UIControlEventValueChanged];

    UIButton *animate = [UIButton buttonWithType:UIButtonTypeSystem];
    [animate setTitle:@"▶︎ 动画：宽度 100% → 35% → 100%" forState:UIControlStateNormal];
    animate.titleLabel.font = [UIFont systemFontOfSize:13];
    animate.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [animate addTarget:self action:@selector(animate30) forControlEvents:UIControlEventTouchUpInside];

    UILabel *hint = [OCCardView label:@"宽度（拖动滑块）/ 对齐 / 行数与内边距" font:[UIFont systemFontOfSize:11]
                                color:[UIColor colorWithWhite:0 alpha:0.45]];
    UILabel *status = [OCCardView label:@"" font:[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular]
                                  color:[UIColor colorWithWhite:0 alpha:0.7]];
    self.case30Status = status;

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[hint, slider, alignment, lines, animate, container, status]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;

    OCDemoCard *card = [[OCDemoCard alloc] initWithTitle:name source:source content:content];
    self.cards[name] = card;
    [self.stackView addArrangedSubview:card];
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh30]; });
}

/// 修改宽度比例：替换宽度约束（multiplier 只读）
- (void)setWidthRatio30:(CGFloat)ratio {
    ZLRichLabel *label = self.case30Label;
    UIView *container = label.superview;
    if (!label || !container) return;
    self.case30Width.active = NO;
    NSLayoutConstraint *width = [label.widthAnchor constraintEqualToAnchor:container.widthAnchor multiplier:ratio];
    width.active = YES;
    self.case30Width = width;
}

- (void)width30:(UISlider *)sender {
    [self setWidthRatio30:sender.value];
    [self.view layoutIfNeeded];   // 只改了约束，label 在布局时（layoutSubviews）自动重新定位 View
    [self refresh30];
}

- (void)alignment30:(UISegmentedControl *)sender {
    NSTextAlignment values[] = {NSTextAlignmentNatural, NSTextAlignmentLeft, NSTextAlignmentCenter, NSTextAlignmentRight};
    self.case30Label.textAlignment = values[sender.selectedSegmentIndex];
    [self.view layoutIfNeeded];
    [self refresh30];
}

- (void)lines30:(UISegmentedControl *)sender {
    ZLRichLabel *label = self.case30Label;
    switch (sender.selectedSegmentIndex) {
        case 0: label.numberOfLines = 0; break;
        case 1: label.numberOfLines = 2; label.lineBreakMode = NSLineBreakByTruncatingTail; break;
        case 2: label.textInsets = UIEdgeInsetsZero; break;
        default: label.textInsets = UIEdgeInsetsMake(8, 16, 8, 16); break;
    }
    [UIView animateWithDuration:0.25 animations:^{ [self.view layoutIfNeeded]; }
                     completion:^(BOOL finished) { [self refresh30]; }];
}

- (void)animate30 {
    [self setWidthRatio30:0.35];
    [self.case30Slider setValue:0.35 animated:YES];
    [UIView animateWithDuration:0.8 animations:^{ [self.view layoutIfNeeded]; } completion:^(BOOL finished) {
        [self refresh30];
        [self setWidthRatio30:1];
        [self.case30Slider setValue:1 animated:YES];
        [UIView animateWithDuration:0.8 delay:0.4 options:0 animations:^{ [self.view layoutIfNeeded]; }
                         completion:^(BOOL done) { [self refresh30]; }];
    }];
}

/// 按钮自己处理点击：文字变长 / 变短，尺寸自动计算，通知 label 重新排版
- (void)follow30:(UITapGestureRecognizer *)gesture {
    UILabel *button = (UILabel *)gesture.view;
    if (![button isKindOfClass:UILabel.class]) return;
    self.case30Followed = !self.case30Followed;
    button.text = self.case30Followed ? @"✓ 已关注" : @"+ 关注";
    button.backgroundColor = self.case30Followed ? kGrey : kBlue;
    [button zl_setNeedsRichLabelLayout];
    [self.view layoutIfNeeded];
    [self refresh30];
    ZLTagInfo *info = [[ZLTagInfo alloc] initWithIndex:0 name:@"follow" text:button.text ?: @"" raw:@"[follow]"];
    [self onTap:@"30. 首 / 中 / 尾自定义 View 跟随 label 尺寸" info:info action:@"按钮自己处理点击，尺寸变化"];
}

/// 实时展示：label 宽度 + 每个 View 的 frame，并与它的占位符位置比较
- (void)refresh30 {
    ZLRichLabel *label = self.case30Label;
    UILabel *status = self.case30Status;
    if (!label || !status) return;
    NSString *string = label.attributedText.string ?: @"";
    NSMutableArray<NSNumber *> *ranges = [NSMutableArray array];
    for (NSUInteger i = 0; i < string.length; i++) {
        if ([string characterAtIndex:i] == 0xFFFC) [ranges addObject:@(i)];
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:
        [NSString stringWithFormat:@"label %.0f × %.0f", label.bounds.size.width, label.bounds.size.height]];
    BOOL allOK = YES;
    for (NSUInteger i = 0; i < self.case30Views.count && i < ranges.count; i++) {
        NSString *title = self.case30Views[i][0];
        UIView *view = self.case30Views[i][1];
        if (view.hidden) {
            [lines addObject:[NSString stringWithFormat:@"%@  已截断，隐藏", title]];
            continue;
        }
        CGRect slot = [label boundingRectForCharacterRange:NSMakeRange(ranges[i].unsignedIntegerValue, 1)];
        BOOL ok = fabs(CGRectGetMinX(view.frame) - CGRectGetMinX(slot)) <= 1
            && CGRectGetMidY(view.frame) >= CGRectGetMinY(slot) - 1
            && CGRectGetMidY(view.frame) <= CGRectGetMaxY(slot) + 1;
        allOK = allOK && ok;
        NSString *result = ok ? @"✅ 与文字位置一致"
            : [NSString stringWithFormat:@"❌ 偏离（占位 x=%.0f y=%.0f）", CGRectGetMinX(slot), CGRectGetMinY(slot)];
        [lines addObject:[NSString stringWithFormat:@"%@  x=%5.1f y=%5.1f  %@", title,
                          CGRectGetMinX(view.frame), CGRectGetMinY(view.frame), result]];
    }
    [lines addObject:allOK ? @"结论：所有 View 已跟随 label 尺寸更新" : @"结论：有 View 位置未更新"];
    status.text = [lines componentsJoinedByString:@"\n"];
}

@end
