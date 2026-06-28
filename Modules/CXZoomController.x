#import "../Headers/PLCameraController.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static const CGFloat kZoom1x = 1.0f;
static const CGFloat kZoom2x = 2.0f;
static const CGFloat kZoom3x = 3.0f;
static const CGFloat kSnapThreshold = 0.3f;
static const CGFloat kMaxZoom = 6.0f;

@interface CXZoomController : NSObject
+ (instancetype)sharedController;
- (void)setZoom:(CGFloat)factor onDevice:(AVCaptureDevice *)device animated:(BOOL)animated;
- (CGFloat)snapToLevel:(CGFloat)raw;
@end

@implementation CXZoomController

+ (instancetype)sharedController {
    static CXZoomController *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (CGFloat)snapToLevel:(CGFloat)raw {
    if (fabs(raw - kZoom1x) < kSnapThreshold) return kZoom1x;
    if (fabs(raw - kZoom2x) < kSnapThreshold) return kZoom2x;
    if (fabs(raw - kZoom3x) < kSnapThreshold) return kZoom3x;
    return raw;
}

- (void)setZoom:(CGFloat)factor onDevice:(AVCaptureDevice *)device animated:(BOOL)animated {
    if (!device) return;
    NSError *err;
    if (![device lockForConfiguration:&err]) {
        NSLog(@"[CinematicX] Zoom lock failed: %@", err);
        return;
    }
    CGFloat maxZ = MIN(device.activeFormat.videoMaxZoomFactor, kMaxZoom);
    CGFloat clamped = MAX(kZoom1x, MIN(factor, maxZ));
    if (animated) {
        [device rampToVideoZoomFactor:clamped withRate:8.0f];
    } else {
        device.videoZoomFactor = clamped;
    }
    [device unlockForConfiguration];

    // Haptic on snap points
    if (fabs(clamped - kZoom1x) < 0.05 ||
        fabs(clamped - kZoom2x) < 0.05 ||
        fabs(clamped - kZoom3x) < 0.05) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc]
                                             initWithStyle:UIImpactFeedbackStyleLight];
            [h impactOccurred];
        });
    }
    NSLog(@"[CinematicX] Zoom → %.1fx", clamped);
}

@end

%hook PLCameraController
- (void)setVideoZoomFactor:(CGFloat)factor {
    AVCaptureDevice *dev = [self valueForKey:@"_videoCaptureDevice"];
    [[CXZoomController sharedController] setZoom:factor onDevice:dev animated:YES];
}
%end
