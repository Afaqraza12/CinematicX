// CXZoomController.x

#import "../Headers/PLCameraController.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// Zoom snap points — feel natural like native iOS
static const CGFloat kZoom1x = 1.0f;
static const CGFloat kZoom2x = 2.0f;
static const CGFloat kZoom3x = 3.0f;
static const CGFloat kZoomSnapThreshold = 0.3f; // snap within 0.3x of target

// Smooth zoom animation duration
static const NSTimeInterval kZoomAnimationDuration = 0.25;

@interface CXZoomController : NSObject
+ (instancetype)sharedController;
- (void)setZoom:(CGFloat)factor onDevice:(AVCaptureDevice *)device animated:(BOOL)animated;
- (CGFloat)snapToNearestLevel:(CGFloat)rawFactor;
- (void)triggerHapticForZoomLevel:(CGFloat)level;
@end

@implementation CXZoomController

+ (instancetype)sharedController {
    static CXZoomController *instance;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ instance = [self new]; });
    return instance;
}

- (CGFloat)snapToNearestLevel:(CGFloat)rawFactor {
    // Snap logic — feel like native camera
    if (fabs(rawFactor - kZoom1x) < kZoomSnapThreshold) return kZoom1x;
    if (fabs(rawFactor - kZoom2x) < kZoomSnapThreshold) return kZoom2x;
    if (fabs(rawFactor - kZoom3x) < kZoomSnapThreshold) return kZoom3x;
    return rawFactor; // no snap — free zoom
}

- (void)triggerHapticForZoomLevel:(CGFloat)level {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] 
                                          initWithStyle:UIImpactFeedbackStyleLight];
    [haptic prepare];
    [haptic impactOccurred];
}

- (void)setZoom:(CGFloat)factor onDevice:(AVCaptureDevice *)device animated:(BOOL)animated {
    if (!device) return;
    
    NSError *error;
    if (![device lockForConfiguration:&error]) {
        NSLog(@"[CinematicX] Failed to lock device: %@", error);
        return;
    }
    
    // Clamp to device supported range
    CGFloat maxZoom = MIN(device.activeFormat.videoMaxZoomFactor, 6.0f);
    CGFloat clampedFactor = MAX(kZoom1x, MIN(factor, maxZoom));
    
    if (animated) {
        [device rampToVideoZoomFactor:clampedFactor withRate:8.0f];
    } else {
        device.videoZoomFactor = clampedFactor;
    }
    
    [device unlockForConfiguration];
    NSLog(@"[CinematicX] Zoom set to %.1fx", clampedFactor);
}

@end

// HOOK PLCameraController zoom
%hook PLCameraController

- (void)setVideoZoomFactor:(CGFloat)factor {
    AVCaptureDevice *device = [self valueForKey:@"_videoCaptureDevice"];
    [[CXZoomController sharedController] setZoom:factor onDevice:device animated:YES];
}

- (CGFloat)videoZoomFactor {
    return %orig;
}

%end
