#import <UIKit/UIKit.h>

// iOS 27 风格状态栏电池：无描边实心胶囊，电量数字镂空在电池内部。
// 只替换状态栏里的 _UIBatteryView（锁屏充电大电池等不受影响）。

@interface _UIBatteryView : UIView
@property (nonatomic) CGFloat chargePercent;
@property (nonatomic) NSInteger chargingState;
@property (nonatomic) BOOL saverModeActive;
@property (nonatomic, copy) UIColor *bodyColor;
@property (nonatomic, strong) CALayer *b27_layer;
@property (nonatomic, copy) NSString *b27_key;
@property (nonatomic, assign) BOOL b27_active;
- (void)b27_refresh;
@end

static UIImage *B27Render(CGSize size, CGFloat pct, BOOL charging, UIColor *base, UIColor *fill) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef ctx = rc.CGContext;
        CGFloat H = size.height, W = size.width;
        CGFloat nubW = H * 0.11, gap = H * 0.08, nubH = H * 0.34;
        CGFloat bodyW = W - nubW - gap;
        UIColor *track = [base colorWithAlphaComponent:0.4];

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

        // 数字（充电时后面跟一个小闪电），放不下就缩小字号
        NSString *text = [NSString stringWithFormat:@"%ld", (long)lround(pct * 100)];
        CGFloat fontSize = H * 0.83;
        NSDictionary *attrs = nil;
        UIFont *font = nil;
        UIImage *bolt = nil;
        CGSize textSize = CGSizeZero;
        CGFloat boltW = 0;
        for (;;) {
            font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightBold];
            attrs = @{ NSFontAttributeName: font,
                       NSForegroundColorAttributeName: UIColor.blackColor,
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
    }];
}

%hook _UIBatteryView

%property (nonatomic, strong) CALayer *b27_layer;
%property (nonatomic, copy) NSString *b27_key;
%property (nonatomic, assign) BOOL b27_active;

%new(v@:)
- (void)b27_refresh {
    if (!self.b27_active) return;
    CGRect bounds = self.bounds;
    if (bounds.size.height < 1) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    CALayer *mine = self.b27_layer;
    if (!mine) {
        mine = [CALayer layer];
        mine.contentsScale = UIScreen.mainScreen.scale;
        self.b27_layer = mine;
    }
    if (mine.superlayer != self.layer) [self.layer addSublayer:mine];

    // 隐藏系统原有的电池图层
    for (CALayer *l in [self.layer.sublayers copy]) {
        if (l != mine && !l.hidden) l.hidden = YES;
    }

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

    CGFloat scale = mine.contentsScale;
    CGFloat H = round(bounds.size.height * 1.13 * 0.95 * scale) / scale;
    CGFloat W = round(H * 27.0 / 13.0 * scale) / scale;
    mine.frame = CGRectMake(round((bounds.size.width - W) / 2 * scale) / scale,
                            round((bounds.size.height - H) / 2 * scale) / scale, W, H);

    NSString *key = [NSString stringWithFormat:@"%ld|%d|%d|%@|%.2f", (long)lround(pct * 100), charging, saver, base, H];
    if (![key isEqualToString:self.b27_key]) {
        self.b27_key = key;
        mine.contents = (__bridge id)B27Render(CGSizeMake(W, H), pct, charging, base, fill).CGImage;
    }

    [CATransaction commit];
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window || self.b27_active) return;
    Class statusBar = %c(_UIStatusBar);
    for (UIView *v = self.superview; v; v = v.superview) {
        if ([v isKindOfClass:statusBar]) {
            self.b27_active = YES;
            [self b27_refresh];
            break;
        }
    }
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

%end
