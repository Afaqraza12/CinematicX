#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// Global cinematic state — checked by frame pipeline
BOOL gCinematicEnabled = NO;
CGFloat gBlurIntensity = 0.7f;

// Provide a dummy AVCaptureDevice if needed (from Tweak.x)
AVCaptureDevice *gActiveDevice = nil;

// Spoof hardware capabilities to show the Cinematic mode dial
%hook CAMCaptureCapabilities

- (BOOL)isCinematicModeSupported {
    return YES;
}

- (BOOL)cinematicModeSupported {
    return YES;
}

- (BOOL)isCinematicVideoSupported {
    return YES;
}

%end

// Monitor mode changes in the Viewfinder to sync our gCinematicEnabled state
// Mode 7 is CAMCaptureModeCinematic in iOS 15+
%hook CAMViewfinderViewController

- (void)_updateForMode:(NSInteger)mode {
    %orig;
    gCinematicEnabled = (mode == 7);
    NSLog(@"[CinematicX] Native Mode updated to %ld. Cinematic enabled: %d", (long)mode, gCinematicEnabled);
}

- (void)changeToMode:(NSInteger)mode devicePosition:(NSInteger)position animated:(BOOL)animated {
    %orig;
    gCinematicEnabled = (mode == 7);
    NSLog(@"[CinematicX] Native Mode changed to %ld. Cinematic enabled: %d", (long)mode, gCinematicEnabled);
}

%end
