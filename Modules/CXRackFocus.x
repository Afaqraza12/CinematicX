#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

static const NSTimeInterval kRackMin = 0.4;
static const NSTimeInterval kRackMax = 0.8;
static const CGFloat kBreathAmp = 0.015f;
static const NSTimeInterval kBreathPeriod = 2.0;
static const CGFloat kRackTriggerDelta = 0.12f;

@interface CXRackFocus : NSObject
@property (nonatomic, weak) AVCaptureDevice *device;
@property (nonatomic, assign) CGPoint focusPoint;
@property (nonatomic, assign) BOOL racking;
@property (nonatomic, strong) NSTimer *breathTimer;
@property (nonatomic, assign) CGFloat breathPhase;
+ (instancetype)sharedRackFocus;
- (void)setDevice:(AVCaptureDevice *)device;
- (void)evaluateRack:(CGRect)oldBox newBox:(CGRect)newBox;
- (void)tapFocusAt:(CGPoint)pt inView:(UIView *)view;
- (void)startBreathing;
- (void)stopBreathing;
@end

@implementation CXRackFocus

+ (instancetype)sharedRackFocus {
    static CXRackFocus *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (void)setDevice:(AVCaptureDevice *)device { _device = device; }

- (void)evaluateRack:(CGRect)oldBox newBox:(CGRect)newBox {
    if (self.racking) return;
    CGPoint oldC = CGPointMake(CGRectGetMidX(oldBox), CGRectGetMidY(oldBox));
    CGPoint newC = CGPointMake(CGRectGetMidX(newBox), CGRectGetMidY(newBox));
    CGFloat d = hypot(newC.x - oldC.x, newC.y - oldC.y);
    if (d < kRackTriggerDelta) return;
    [self rackToPoint:newC distance:d];
}

- (void)rackToPoint:(CGPoint)pt distance:(CGFloat)d {
    self.racking = YES;
    [self stopBreathing];
    AVCaptureDevice *dev = self.device;
    if (!dev) { self.racking = NO; return; }

    NSError *err;
    if (![dev lockForConfiguration:&err]) { self.racking = NO; return; }
    dev.exposureMode = AVCaptureExposureModeLocked;
    if ([dev isFocusPointOfInterestSupported]) {
        dev.focusPointOfInterest = pt;
        dev.focusMode = AVCaptureFocusModeAutoFocus;
    }
    [dev unlockForConfiguration];

    NSTimeInterval dur = kRackMin + (d * (kRackMax - kRackMin));
    NSLog(@"[CinematicX] Rack focus → %.2f,%.2f dur:%.2fs", pt.x, pt.y, dur);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(dur * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSError *e;
        if ([dev lockForConfiguration:&e]) {
            dev.focusMode = AVCaptureFocusModeContinuousAutoFocus;
            dev.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
            [dev unlockForConfiguration];
        }
        self.racking = NO;
        [self startBreathing];
    });
}

- (void)tapFocusAt:(CGPoint)screenPt inView:(UIView *)view {
    CGPoint norm = CGPointMake(screenPt.x / view.bounds.size.width,
                                screenPt.y / view.bounds.size.height);
    AVCaptureDevice *dev = self.device;
    if (!dev) return;
    NSError *e;
    if ([dev lockForConfiguration:&e]) {
        if ([dev isFocusPointOfInterestSupported]) {
            dev.focusPointOfInterest = norm;
            dev.focusMode = AVCaptureFocusModeAutoFocus;
        }
        [dev unlockForConfiguration];
    }
}

- (void)startBreathing {
    self.breathPhase = 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.breathTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                            target:self
                                                          selector:@selector(breathTick)
                                                          userInfo:nil
                                                           repeats:YES];
    });
}

- (void)stopBreathing {
    [self.breathTimer invalidate];
    self.breathTimer = nil;
}

- (void)breathTick {
    AVCaptureDevice *dev = self.device;
    if (!dev || self.racking) return;
    self.breathPhase += (0.05 / kBreathPeriod) * 2 * M_PI;
    CGFloat offset = sin(self.breathPhase) * kBreathAmp;
    NSError *e;
    if ([dev lockForConfiguration:&e]) {
        dev.videoZoomFactor = MAX(1.0, dev.videoZoomFactor + offset);
        [dev unlockForConfiguration];
    }
}

@end
