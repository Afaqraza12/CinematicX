#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// Forward declare CXZoomController to avoid circular imports if needed, or simply use NSClassFromString
@interface CXZoomController : NSObject
+ (instancetype)sharedController;
- (void)setZoom:(CGFloat)factor onDevice:(id)device animated:(BOOL)animated;
@end

static UIColor *CXYellow() { return [UIColor colorWithRed:1.0 green:0.84 blue:0.0 alpha:1.0]; }
static UIColor *CXBG()     { return [UIColor colorWithWhite:0.0 alpha:0.45]; }
static UIColor *CXWhite()  { return [UIColor colorWithWhite:1.0 alpha:0.9]; }

// Global cinematic state — checked by frame pipeline
BOOL gCinematicEnabled = NO;
CGFloat gBlurIntensity = 0.7f;

// Active capture device, published by the Tweak.x pipeline each frame so the overlay's
// zoom pills can drive real zoom (fixes the "onDevice:nil does nothing" bug).
AVCaptureDevice *gActiveDevice = nil;

@interface CXOverlayView : UIView
@property (nonatomic, strong) UIButton *btn1x, *btn2x, *btn3x;
@property (nonatomic, strong) UIButton *cineBtn;
@property (nonatomic, strong) UIView *focusBox;
@property (nonatomic, strong) UISlider *blurSlider;
@property (nonatomic, strong) NSTimer *hideTimer;
- (void)showFocusAt:(CGPoint)pt;
- (void)lockFocus;
- (void)setZoomActive:(CGFloat)z;
- (void)resetHide;
@end

@implementation CXOverlayView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        [self buildUI];
    }
    return self;
}

// Pass-through hit testing: the overlay spans the whole preview, but only OUR controls
// should capture touches. Empty areas fall through to the Camera app underneath so the
// native shutter, mode switcher and pinch-to-zoom keep working (fixes touch-blocking).
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}

- (void)buildUI {
    // Zoom pill container
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 2;
    stack.backgroundColor = CXBG();
    stack.layer.cornerRadius = 18;
    stack.layoutMargins = UIEdgeInsetsMake(5, 10, 5, 10);
    stack.layoutMarginsRelativeArrangement = YES;

    self.btn1x = [self makeZoomBtn:@"1×" zoom:1.0];
    self.btn2x = [self makeZoomBtn:@"2×" zoom:2.0];
    self.btn3x = [self makeZoomBtn:@"3×" zoom:3.0];
    [stack addArrangedSubview:self.btn1x];
    [stack addArrangedSubview:self.btn2x];
    [stack addArrangedSubview:self.btn3x];
    [self addSubview:stack];

    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor
                                           constant:-130]
    ]];

    // CINE toggle
    self.cineBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cineBtn setTitle:@"CINE" forState:UIControlStateNormal];
    self.cineBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [self.cineBtn setTitleColor:CXWhite() forState:UIControlStateNormal];
    self.cineBtn.backgroundColor = CXBG();
    self.cineBtn.layer.cornerRadius = 12;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.cineBtn.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
#pragma clang diagnostic pop
    [self.cineBtn addTarget:self action:@selector(toggleCine)
          forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.cineBtn];
    self.cineBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.cineBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.cineBtn.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor
                                               constant:16]
    ]];

    // Focus square
    self.focusBox = [[UIView alloc] initWithFrame:CGRectMake(0,0,80,80)];
    self.focusBox.layer.borderColor = CXYellow().CGColor;
    self.focusBox.layer.borderWidth = 1.5;
    self.focusBox.layer.cornerRadius = 4;
    self.focusBox.alpha = 0;
    [self addSubview:self.focusBox];

    // Blur slider (vertical, right edge)
    self.blurSlider = [UISlider new];
    self.blurSlider.minimumValue = 0.0;
    self.blurSlider.maximumValue = 1.0;
    self.blurSlider.value = 0.7;
    self.blurSlider.tintColor = CXYellow();
    self.blurSlider.transform = CGAffineTransformMakeRotation(-M_PI_2);
    self.blurSlider.hidden = YES;
    [self.blurSlider addTarget:self action:@selector(blurChanged:)
              forControlEvents:UIControlEventValueChanged];
    [self addSubview:self.blurSlider];
    self.blurSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.blurSlider.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.blurSlider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.blurSlider.widthAnchor constraintEqualToConstant:130]
    ]];

    [self resetHide];
}

- (UIButton *)makeZoomBtn:(NSString *)t zoom:(CGFloat)z {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    [b setTitleColor:CXYellow() forState:UIControlStateNormal];
    b.tag = (NSInteger)(z * 10);
    [b addTarget:self action:@selector(zoomTap:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)zoomTap:(UIButton *)b {
    CGFloat z = b.tag / 10.0;
    // Drive the REAL active device (published by the pipeline), not nil.
    [[NSClassFromString(@"CXZoomController") sharedController] setZoom:z onDevice:gActiveDevice animated:YES];
    [self setZoomActive:z];
    [self resetHide];
}

- (void)toggleCine {
    gCinematicEnabled = !gCinematicEnabled;
    self.blurSlider.hidden = !gCinematicEnabled;

    // The CINE button is the dedicated Cinematic-mode entry. Make its state obvious:
    // filled yellow when ON, translucent when OFF. Cinematic features (depth bokeh,
    // tracking, rack focus) only run while this is ON — never in plain video mode.
    if (gCinematicEnabled) {
        self.cineBtn.backgroundColor = CXYellow();
        [self.cineBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    } else {
        self.cineBtn.backgroundColor = CXBG();
        [self.cineBtn setTitleColor:CXWhite() forState:UIControlStateNormal];
    }
    NSLog(@"[CinematicX] Cinematic: %@", gCinematicEnabled ? @"ON" : @"OFF");
    [self resetHide];
}

- (void)blurChanged:(UISlider *)s {
    gBlurIntensity = s.value;
}

- (void)setZoomActive:(CGFloat)z {
    for (UIButton *b in @[self.btn1x, self.btn2x, self.btn3x]) {
        BOOL active = fabs(b.tag/10.0 - z) < 0.1;
        [b setTitleColor:active ? CXYellow() : CXWhite() forState:UIControlStateNormal];
    }
}

- (void)showFocusAt:(CGPoint)pt {
    self.focusBox.center = pt;
    self.focusBox.transform = CGAffineTransformMakeScale(1.4, 1.4);
    self.focusBox.alpha = 1.0;
    [UIView animateWithDuration:0.25 animations:^{
        self.focusBox.transform = CGAffineTransformIdentity;
    }];
}

- (void)lockFocus {
    [UIView animateWithDuration:0.2 animations:^{
        self.focusBox.transform = CGAffineTransformMakeScale(0.75, 0.75);
    } completion:^(BOOL _) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ self.focusBox.alpha = 0; }];
        });
    }];
}

- (void)resetHide {
    [self.hideTimer invalidate];
    self.alpha = 1.0;
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                      target:self
                                                    selector:@selector(hide)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)hide {
    [UIView animateWithDuration:0.5 animations:^{ self.alpha = 0.0; }];
}

- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e {
    [self resetHide];
    [super touchesBegan:t withEvent:e];
}

@end

@interface CAMViewfinderView : UIView
@end

%hook CAMViewfinderView
- (void)didMoveToWindow {
    %orig;
    static CXOverlayView *overlay;
    if (!overlay && self.window) {
        overlay = [[CXOverlayView alloc] initWithFrame:self.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self addSubview:overlay];
        NSLog(@"[CinematicX] Overlay injected");
    }
}
%end
