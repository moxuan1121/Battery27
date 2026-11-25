#import <UIKit/UIKit.h>

// 电池27：把状态栏里的 _UIBatteryView 换成 iOS 27 风格的无描边实心胶囊，电量数字显示在电池内部。
// 只注入 SpringBoard（应用内的状态栏电池在本设备上也由 SpringBoard 绘制）。
// 做法：系统原生的电池图层全部是电池视图的子图层，用 sublayerTransform 整体移出可见范围；
// 我们的图画在电池视图自身图层的 contents 上，系统之后怎么重建、显示子图层都不会露出原生图标。

// 尺寸与字号（按真机反馈逐步调出来的值，保持原样）
static const CGFloat kHeightRatio = 1.13 * 0.95 * 0.97 * 0.97; // 胶囊高度 / 电池视图高度
static const CGFloat kAspect      = 27.0 / 13.0;               // 胶囊宽 / 高
static const CGFloat kFontRatio   = 0.83 * 1.1 * 1.1;          // 数字字号 / 胶囊高度

@interface _UIBatteryView : UIView
@property (nonatomic) CGFloat chargePercent;
@property (nonatomic) NSInteger chargingState;
@property (nonatomic) BOOL saverModeActive;
@property (nonatomic, copy) UIColor *bodyColor;
@property (nonatomic, copy) UIColor *fillColor;
// 本插件新增
@property (nonatomic, assign) BOOL b27_active;
@property (nonatomic, copy) NSString *b27_key;
- (void)b27_refresh;
@end

// 状态栏里是否已有单独的百分比文字（控制中心展开的状态栏就有），有则电池里不再重复显示数字
static BOOL HasPercentLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        return !view.hidden && [((UILabel *)view).text containsString:@"%"];
    }
    for (UIView *sub in view.subviews) {
        if (HasPercentLabel(sub)) return YES;
    }
    return NO;
}

static UIView *EnclosingStatusBar(UIView *view) {
    Class statusBarClass = %c(_UIStatusBar);
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v isKindOfClass:statusBarClass]) return v;
    }
    return nil;
}

static BOOL IsDark(UIColor *color) {
    CGFloat r = 1, g = 1, b = 1;
    [color getRed:&r green:&g blue:&b alpha:NULL];
    return 0.299 * r + 0.587 * g + 0.114 * b < 0.5;
}

// pct: 0~1；plain: 只画电池不画数字；darkInk: 数字用黑色实心（省电模式）而不是镂空
static UIImage *Render(CGSize size, CGFloat pct, BOOL charging, BOOL darkInk, BOOL plain, UIColor *base, UIColor *fill) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef ctx = rc.CGContext;
        CGFloat H = size.height, W = size.width;
        CGFloat nubW = H * 0.11, gap = H * 0.08, nubH = H * 0.34;
        CGFloat bodyW = W - nubW - gap;

        // 未填充段：省电模式黑字在浅色背景（前景色为深色）时调浅，黑字才看得清
        UIColor *track = [base colorWithAlphaComponent:(darkInk && IsDark(base)) ? 0.25 : 0.6];

        // 胶囊底色 + 正极小凸点（充满时凸点用填充色）
        UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, bodyW, H) cornerRadius:H * 0.31];
        [track setFill];
        [body fill];
        UIBezierPath *nub = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(bodyW + gap, (H - nubH) / 2, nubW, nubH)
                                                  byRoundingCorners:UIRectCornerTopRight | UIRectCornerBottomRight
                                                        cornerRadii:CGSizeMake(nubW, nubW)];
        [(pct >= 0.995 ? fill : track) setFill];
        [nub fill];

        // 电量填充
        CGContextSaveGState(ctx);
        [body addClip];
        [fill setFill];
        UIRectFill(CGRectMake(0, 0, bodyW * pct, H));
        CGContextRestoreGState(ctx);

        if (plain) return;

        // 数字（充电时后面跟一个小闪电），放不下就缩小字号
        NSString *text = [NSString stringWithFormat:@"%ld", lround(pct * 100)];
        CGFloat fontSize = H * kFontRatio;
        NSDictionary *attrs = nil;
        UIFont *font = nil;
        UIImage *bolt = nil;
        CGSize textSize = CGSizeZero;
        CGFloat boltW = 0;
        for (;;) {
            font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightBlack];
            attrs = @{ NSFontAttributeName: font,
                       NSForegroundColorAttributeName: UIColor.blackColor,
                       NSStrokeColorAttributeName: UIColor.blackColor,
                       NSStrokeWidthAttributeName: @(-4), // Black 已是系统最粗，再用描边加粗一档
                       NSKernAttributeName: @(-fontSize * 0.03) };
            textSize = [text sizeWithAttributes:attrs];
            if (charging) {
                UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:fontSize * 0.62 weight:UIImageSymbolWeightBold];
                bolt = [[UIImage systemImageNamed:@"bolt.fill" withConfiguration:cfg] imageWithTintColor:UIColor.blackColor renderingMode:UIImageRenderingModeAlwaysOriginal];
                boltW = bolt.size.width + fontSize * 0.05;
            }
            if (textSize.width + boltW <= bodyW - H * 0.2 || fontSize <= 6) break;
            fontSize -= 0.5;
        }

        // 默认镂空：任何状态栏背景下都清晰
        CGPoint origin = CGPointMake((bodyW - textSize.width - boltW) / 2,
                                     (H - font.capHeight) / 2 - (font.ascender - font.capHeight));
        CGContextSetBlendMode(ctx, kCGBlendModeDestinationOut);
        [text drawAtPoint:origin withAttributes:attrs];
        if (bolt) {
            CGRect r = CGRectMake(origin.x + textSize.width + fontSize * 0.05, (H - bolt.size.height) / 2, bolt.size.width, bolt.size.height);
            [bolt drawInRect:r blendMode:kCGBlendModeDestinationOut alpha:1];
        }

        // 省电模式：整个数字统一用黑色实心（浅色背景下镂空露出白底，在黄色上看不清）
        if (darkInk) {
            CGContextSetBlendMode(ctx, kCGBlendModeNormal);
            [text drawAtPoint:origin withAttributes:attrs];
        }
    }];
}

%hook _UIBatteryView

%property (nonatomic, assign) BOOL b27_active;
%property (nonatomic, copy) NSString *b27_key;

%new(v@:)
- (void)b27_refresh {
    UIView *statusBar = EnclosingStatusBar(self);

    // 只接管状态栏里的电池；任何一次刷新都可以补做接管，不依赖某个固定时机
    if (!self.b27_active) {
        if (!statusBar || !self.window) return;
        self.b27_active = YES;

        CALayer *host = self.layer;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        host.sublayerTransform = CATransform3DMakeTranslation(0, 20000, 0);
        host.masksToBounds = NO;
        host.contentsGravity = kCAGravityCenter;
        host.contentsScale = UIScreen.mainScreen.scale;
        [CATransaction commit];

        // 百分比文字可能晚于电池视图出现，稍后再判断一次
        __weak __typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf b27_refresh];
        });
    }

    CGFloat viewH = self.bounds.size.height;
    if (viewH < 1) return;

    CGFloat pct = self.chargePercent;
    if (pct > 1) pct /= 100;
    pct = MAX(0, MIN(1, pct));
    BOOL charging = self.chargingState != 0;
    BOOL saver = self.saverModeActive;
    BOOL plain = statusBar && HasPercentLabel(statusBar);

    UITraitCollection *traits = self.traitCollection;
    UIColor *base = [[(self.bodyColor ?: self.tintColor) resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:1];
    CGFloat r = 0, g = 0, b = 0;
    [base getRed:&r green:&g blue:&b alpha:NULL];

    CGFloat scale = UIScreen.mainScreen.scale;
    CGFloat H = round(viewH * kHeightRatio * scale) / scale;

    // 外观参数都没变就不重画（layoutSubviews 很频繁，这里是主要的省电点）
    NSString *key = [NSString stringWithFormat:@"%ld|%d%d%d|%.3f,%.3f,%.3f|%.2f", lround(pct * 100), charging, saver, plain, r, g, b, H];
    if ([key isEqualToString:self.b27_key]) return;

    UIColor *fill = base;
    if (charging) fill = UIColor.systemGreenColor;
    else if (saver) fill = UIColor.systemYellowColor;
    else if (pct <= 0.2) fill = UIColor.systemRedColor;
    fill = [fill resolvedColorWithTraitCollection:traits];

    CGFloat W = round(H * kAspect * scale) / scale;
    UIImage *image = Render(CGSizeMake(W, H), pct, charging, saver && !charging && !plain, plain, base, fill);

    CALayer *host = self.layer;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (self.b27_key) {
        // 样式变化时淡入淡出，避免生硬跳变
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = 0.2;
        [host addAnimation:fade forKey:@"b27_fade"];
    }
    host.contents = (__bridge id)image.CGImage;
    [CATransaction commit];
    self.b27_key = key;
}

- (void)didMoveToWindow {
    %orig;
    [self b27_refresh];
}

- (void)didMoveToSuperview {
    %orig;
    [self b27_refresh];
}

- (void)layoutSubviews {
    %orig;
    [self b27_refresh];
}

- (void)setChargePercent:(CGFloat)percent {
    %orig;
    [self b27_refresh];
}

- (void)setChargingState:(NSInteger)state {
    %orig;
    [self b27_refresh];
}

- (void)setSaverModeActive:(BOOL)active {
    %orig;
    [self b27_refresh];
}

- (void)setBodyColor:(UIColor *)color {
    %orig;
    [self b27_refresh];
}

- (void)setFillColor:(UIColor *)color {
    %orig;
    [self b27_refresh];
}

%end
