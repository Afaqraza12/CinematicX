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

%hook AVCaptureSession

- (BOOL)canSetSessionPreset:(NSString *)preset {
    if ([preset isEqualToString:@"AVCaptureSessionPresetCinematic"] || [preset isEqualToString:@"AVAssetExportPresetCinematic"]) {
        return YES;
    }
    return %orig;
}

- (void)setSessionPreset:(NSString *)preset {
    if ([preset isEqualToString:@"AVCaptureSessionPresetCinematic"] || [preset isEqualToString:@"AVAssetExportPresetCinematic"]) {
        NSLog(@"[CinematicX] Downgrading cinematic preset to High to avoid hardware crash.");
        %orig(AVCaptureSessionPresetHigh);
        return;
    }
    %orig;
}

%end

%hook AVCaptureDevice

// Prevent the crash when the native f-stop slider is used
// Instead, feed its value directly to our custom software blur!
- (void)setCinematicVideoSimulatedAperture:(float)aperture {
    NSLog(@"[CinematicX] Intercepted Simulated Aperture: %f", aperture);
    
    // Apple's native aperture slider usually goes from f/2.0 (max blur) to f/16.0 (no blur)
    // We map this inverse scale to our 0.0 - 1.0 blur intensity
    gBlurIntensity = 1.0 - ((aperture - 2.0) / 14.0);
    
    // Clamp values just to be safe
    if (gBlurIntensity < 0.0) gBlurIntensity = 0.0;
    if (gBlurIntensity > 1.0) gBlurIntensity = 1.0;
}

// Return our mapped value when the UI queries it
- (float)cinematicVideoSimulatedAperture {
    float mappedAperture = 16.0 - (gBlurIntensity * 14.0);
    return mappedAperture;
}

- (float)minCinematicVideoSimulatedAperture {
    return 2.0f;
}

- (float)maxCinematicVideoSimulatedAperture {
    return 16.0f;
}

%end
