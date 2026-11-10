#import <UIKit/UIKit.h>

// iOS 27 风格状态栏电池：无描边实心胶囊，电量数字镂空在电池内部。
// 只替换状态栏里的 _UIBatteryView（锁屏充电大电池等不受影响）。

@interface _UIBatteryView : UIView
@property (nonatomic) CGFloat chargePercent;
@property (nonatomic) NSInteger chargingState;
@property (nonatomic) BOOL saverModeActive;
@property (nonatomic, copy) UIColor *bodyColor;
@property (nonatomic, copy) UIColor *fillColor;
@property (nonatomic, copy) NSString *b27_key;
@property (nonatomic, assign) BOOL b27_active;
- (void)b27_refresh;
@end

// 状态栏里是否已经有单独的百分比文字（控制中心展开的状态栏就有）
static BOOL B27HasPercentLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        return !view.hidden && [((UILabel *)view).text containsString:@"%"];
    }
    for (UIView *sub in view.subviews) {
        if (B27HasPercentLabel(sub)) return YES;
    }
    return NO;
}

static UIImage *B27Render(CGSize size, CGFloat pct, BOOL charging, BOOL darkInk, BOOL plain, UIColor *base, UIColor *fill) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef ctx = rc.CGContext;
        CGFloat H = size.height, W = size.width;
        CGFloat nubW = H * 0.11, gap = H * 0.08, nubH = H * 0.34;
        CGFloat bodyW = W - nubW - gap;
        CGFloat trackAlpha = 0.6;
        if (darkInk) {
            // 省电模式数字是黑色：浅色背景（前景色为深色）时把未填充段调浅，黑字才看得清
            CGFloat r = 1, g = 1, b = 1;
            [base getRed:&r green:&g blue:&b alpha:NULL];
            if (0.299 * r + 0.587 * g + 0.114 * b < 0.5) trackAlpha = 0.25;
        }
        UIColor *track = [base colorWithAlphaComponent:trackAlpha];

        // 底色（未充满的部分）+ 正极小凸点
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

        if (plain) return; // 旁边已有百分比文字：只画电池，不画数字

        // 数字（充电时后面跟一个小闪电），放不下就缩小字号
        NSString *text = [NSString stringWithFormat:@"%ld", (long)lround(pct * 100)];
        CGFloat fontSize = H * 0.83 * 1.1 * 1.1;
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

        // 镂空绘制：任何状态栏背景下都清晰
        CGFloat x = (bodyW - textSize.width - boltW) / 2;
        CGFloat y = (H - font.capHeight) / 2 - (font.ascender - font.capHeight);
        CGContextSetBlendMode(ctx, kCGBlendModeDestinationOut);
        [text drawAtPoint:CGPointMake(x, y) withAttributes:attrs];
        if (bolt) {
            CGRect r = CGRectMake(x + textSize.width + fontSize * 0.05, (H - bolt.size.height) / 2, bolt.size.width, bolt.size.height);
            [bolt drawInRect:r blendMode:kCGBlendModeDestinationOut alpha:1];
        }

        // 省电模式：整个数字统一用黑色实心（浅色背景下镂空露出白底，在黄色上看不清）
        if (darkInk) {
            CGContextSetBlendMode(ctx, kCGBlendModeNormal);
            [text drawAtPoint:CGPointMake(x, y) withAttributes:attrs];
        }
    }];
}

%hook _UIBatteryView

%property (nonatomic, copy) NSString *b27_key;
%property (nonatomic, assign) BOOL b27_active;

%new(v@:)
- (void)b27_refresh {
    Class statusBarClass = %c(_UIStatusBar);
    UIView *statusBar = nil;
    for (UIView *v = self.superview; v; v = v.superview) {
        if ([v isKindOfClass:statusBarClass]) { statusBar = v; break; }
    }

    // 只接管状态栏里的电池；每次刷新都可以补做接管，不依赖某一个时机
    if (!self.b27_active) {
        if (!statusBar || !self.window) return;
        self.b27_active = YES;
        // 百分比文字可能晚于电池视图出现，稍后再判断一次
        __weak __typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf b27_refresh];
        });
    }

    CALayer *host = self.layer;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // 系统原生的电池图层全部是子图层：整体移出可见范围。
    // 不管系统之后怎么重建、显示、做动画，原生图标都不会再露出来；我们的图画在视图自身图层上。
    host.sublayerTransform = CATransform3DMakeTranslation(0, 20000, 0);
    host.masksToBounds = NO;
    host.contentsGravity = kCAGravityCenter;
    CGFloat scale = UIScreen.mainScreen.scale;
    host.contentsScale = scale;

    CGRect bounds = self.bounds;
    if (bounds.size.height >= 1) {
        CGFloat pct = self.chargePercent;
        if (pct > 1) pct /= 100;
        pct = MAX(0, MIN(1, pct));
        BOOL charging = self.chargingState != 0;
        BOOL saver = self.saverModeActive;

        UIColor *base = self.bodyColor ?: self.tintColor ?: UIColor.labelColor;
        base = [[base resolvedColorWithTraitCollection:self.traitCollection] colorWithAlphaComponent:1];
        UIColor *fill = base;
        if (charging) fill = UIColor.systemGreenColor;
        else if (saver) fill = UIColor.systemYellowColor;
        else if (pct <= 0.2) fill = UIColor.systemRedColor;

        // 所在状态栏已有“29%”这样的文字时（控制中心），电池里不再重复显示数字
        BOOL plain = statusBar && B27HasPercentLabel(statusBar);

        CGFloat H = round(bounds.size.height * 1.13 * 0.95 * 0.97 * 0.97 * scale) / scale;
        CGFloat W = round(H * 27.0 / 13.0 * scale) / scale;

        NSString *key = [NSString stringWithFormat:@"%ld|%d|%d|%d|%@|%.2f", (long)lround(pct * 100), charging, saver, plain, base, H];
        if (![key isEqualToString:self.b27_key]) {
            if (self.b27_key) {
                // 样式变化时淡入淡出，避免生硬跳变
                CATransition *fade = [CATransition animation];
                fade.type = kCATransitionFade;
                fade.duration = 0.2;
                [host addAnimation:fade forKey:@"b27_fade"];
            }
            self.b27_key = key;
            host.contents = (__bridge id)B27Render(CGSizeMake(W, H), pct, charging, saver && !charging && !plain, plain, base, fill).CGImage;
        }
    }

    [CATransaction commit];
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
