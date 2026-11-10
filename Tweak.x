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
@property (nonatomic, assign) BOOL b27_plain;
- (void)b27_refresh;
@end

static UIImage *B27Render(CGSize size, CGFloat pct, BOOL charging, BOOL plain, UIColor *base, UIColor *fill) {
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

        if (plain) return; // 控制中心：旁边已有百分比文字，电池内不画数字

        // 数字（充电时后面跟一个小闪电），放不下就缩小字号
        NSString *text = [NSString stringWithFormat:@"%ld", (long)lround(pct * 100)];
        CGFloat fontSize = H * 0.95;
        NSDictionary *attrs = nil;
        UIFont *font = nil;
        UIImage *bolt = nil;
        CGSize textSize = CGSizeZero;
        CGFloat boltW = 0;
        for (;;) {
            font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightBold];
            attrs = @{ NSFontAttributeName: font,
                       NSForegroundColorAttributeName: base,
                       NSKernAttributeName: @(-fontSize * 0.03) };
            textSize = [text sizeWithAttributes:attrs];
            if (charging) {
                UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:fontSize * 0.62 weight:UIImageSymbolWeightBold];
                bolt = [[UIImage systemImageNamed:@"bolt.fill" withConfiguration:cfg] imageWithTintColor:base renderingMode:UIImageRenderingModeAlwaysOriginal];
                boltW = bolt.size.width + fontSize * 0.05;
            }
            if (textSize.width + boltW <= bodyW - H * 0.2 || fontSize <= 6) break;
            fontSize -= 0.5;
        }

        CGFloat x = (bodyW - textSize.width - boltW) / 2;
        CGFloat y = (H - font.capHeight) / 2 - (font.ascender - font.capHeight);
        CGPoint textPoint = CGPointMake(x, y);
        CGRect boltRect = CGRectMake(x + textSize.width + fontSize * 0.05, (H - bolt.size.height) / 2, bolt.size.width, bolt.size.height);
        CGFloat split = bodyW * pct;

        // iOS 27：落在已填充部分的数字镂空，落在未填充部分的数字用前景色实心
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, CGRectMake(0, 0, split, H));
        CGContextSetBlendMode(ctx, kCGBlendModeDestinationOut);
        [text drawAtPoint:textPoint withAttributes:attrs];
        if (bolt) [bolt drawInRect:boltRect blendMode:kCGBlendModeDestinationOut alpha:1];
        CGContextRestoreGState(ctx);

        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, CGRectMake(split, 0, W - split, H));
        CGContextSetBlendMode(ctx, kCGBlendModeCopy);
        [text drawAtPoint:textPoint withAttributes:attrs];
        if (bolt) [bolt drawInRect:boltRect blendMode:kCGBlendModeCopy alpha:1];
        CGContextRestoreGState(ctx);
    }];
}

%hook _UIBatteryView

%property (nonatomic, strong) CALayer *b27_layer;
%property (nonatomic, copy) NSString *b27_key;
%property (nonatomic, assign) BOOL b27_active;
%property (nonatomic, assign) BOOL b27_plain;

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
    // 比例取自 iOS 27 截图：状态栏电池高约为旁边文字大写高度的 1.3 倍，控制中心约 1.1 倍
    BOOL plain = self.b27_plain;
    CGFloat H = round(bounds.size.height * (plain ? 0.75 : 0.88) * scale) / scale;
    CGFloat W = round(H * (plain ? 2.2 : 27.0 / 13.0) * scale) / scale;
    mine.frame = CGRectMake(round((bounds.size.width - W) / 2 * scale) / scale,
                            round((bounds.size.height - H) / 2 * scale) / scale, W, H);

    NSString *key = [NSString stringWithFormat:@"%ld|%d|%d|%d|%@|%.2f", (long)lround(pct * 100), charging, saver, plain, base, H];
    if (![key isEqualToString:self.b27_key]) {
        self.b27_key = key;
        mine.contents = (__bridge id)B27Render(CGSizeMake(W, H), pct, charging, plain, base, fill).CGImage;
    }

    [CATransaction commit];
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window || self.b27_active) return;
    Class statusBar = %c(_UIStatusBar);
    BOOL inStatusBar = NO, inControlCenter = NO;
    for (UIView *v = self.superview; v; v = v.superview) {
        if ([v isKindOfClass:statusBar]) inStatusBar = YES;
        else if ([NSStringFromClass(v.class) hasPrefix:@"CCUI"]) inControlCenter = YES;
    }
    if (!inStatusBar) return;
    self.b27_plain = inControlCenter;
    self.b27_active = YES;
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

%end
