#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import "Headers/PLCameraController.h"

// --- Interface Declarations to satisfy compiler ---
@interface CXDepthEngine : NSObject
+ (instancetype)sharedEngine;
- (CIImage *)latestDepthImage; // newest disparity map, or nil
@end

@interface CXBokehRenderer : NSObject
@property (nonatomic, strong) CIContext *context;
+ (instancetype)sharedRenderer;
- (CIImage *)renderBokehForImage:(CIImage *)inputImage
                        withMask:(CIImage *)maskImage
                           depth:(CIImage *)depthImage
                       intensity:(CGFloat)intensity;
@end

@interface CXEdgeDetector : NSObject
+ (instancetype)sharedDetector;
- (void)submitFrame:(CVPixelBufferRef)pixelBuffer; // async — runs Vision off the capture thread
- (CIImage *)latestMaskImage;                      // newest mask, or nil if none yet
@end

@interface CXSubjectTracker : NSObject
+ (instancetype)sharedTracker;
- (void)processFrame:(CMSampleBufferRef)buf completion:(void(^)(CGRect box, BOOL needsReseg))cb;
@end

@interface CXRackFocus : NSObject
+ (instancetype)sharedRackFocus;
- (void)setDevice:(AVCaptureDevice *)device;
- (void)evaluateRack:(CGRect)oldBox newBox:(CGRect)newBox;
@end

// Global state (set by CXOverlayUI)
extern BOOL gCinematicEnabled;
extern CGFloat gBlurIntensity;

// Master enable from the Settings panel (com.afaq.cinematicx → "enabled").
// Defaults to YES when the key is absent so a fresh install is active.
static BOOL gTweakEnabled = YES;

static void CXReloadPrefs(void) {
    NSString *path = @"/var/jb/var/mobile/Library/Preferences/com.afaq.cinematicx.plist";
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!prefs) // rootless fallback to legacy location
        prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.afaq.cinematicx"];
    id v = prefs[@"enabled"];
    gTweakEnabled = (v == nil) ? YES : [v boolValue];
}

static void CXPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    CXReloadPrefs();
}

%ctor {
    CXReloadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, CXPrefsChangedCallback,
        CFSTR("com.afaq.cinematicx/prefsChanged"),
        NULL, CFNotificationSuspensionBehaviorCoalesce);
}

// Copies pixel data from src into dst (handles both planar and packed formats),
// honoring each buffer's own bytes-per-row. Used to move our rendered result back
// into the camera's buffer without reading and writing the same buffer at once.
static void CXCopyPixelBuffer(CVPixelBufferRef src, CVPixelBufferRef dst) {
    CVPixelBufferLockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(dst, 0);
    if (CVPixelBufferIsPlanar(src)) {
        size_t planes = CVPixelBufferGetPlaneCount(src);
        for (size_t p = 0; p < planes; p++) {
            uint8_t *s = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(src, p);
            uint8_t *d = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(dst, p);
            size_t srcBPR = CVPixelBufferGetBytesPerRowOfPlane(src, p);
            size_t dstBPR = CVPixelBufferGetBytesPerRowOfPlane(dst, p);
            size_t h = CVPixelBufferGetHeightOfPlane(src, p);
            size_t copyBPR = MIN(srcBPR, dstBPR);
            for (size_t row = 0; row < h; row++)
                memcpy(d + row * dstBPR, s + row * srcBPR, copyBPR);
        }
    } else {
        uint8_t *s = (uint8_t *)CVPixelBufferGetBaseAddress(src);
        uint8_t *d = (uint8_t *)CVPixelBufferGetBaseAddress(dst);
        size_t srcBPR = CVPixelBufferGetBytesPerRow(src);
        size_t dstBPR = CVPixelBufferGetBytesPerRow(dst);
        size_t h = CVPixelBufferGetHeight(src);
        size_t copyBPR = MIN(srcBPR, dstBPR);
        for (size_t row = 0; row < h; row++)
            memcpy(d + row * dstBPR, s + row * srcBPR, copyBPR);
    }
    CVPixelBufferUnlockBaseAddress(dst, 0);
    CVPixelBufferUnlockBaseAddress(src, kCVPixelBufferLock_ReadOnly);
}

// --- Main Pipeline ---

%hook PLCameraController

- (CMSampleBufferRef)_processedSampleBuffer:(CMSampleBufferRef)buffer {
    CMSampleBufferRef original = %orig(buffer);

    // Always publish the active device while the tweak is enabled — the overlay's zoom
    // pills work in any mode, so this must run even when Cinematic Mode is off.
    if (gTweakEnabled) {
        AVCaptureDevice *activeDev = [self valueForKey:@"_videoCaptureDevice"];
        extern AVCaptureDevice *gActiveDevice;
        gActiveDevice = activeDev;
    }

    // Fast path: skip the heavy cinematic pipeline if the tweak is disabled in Settings,
    // or Cinematic Mode isn't toggled on in the Camera UI.
    if (!gTweakEnabled || !gCinematicEnabled) return original;

    CXEdgeDetector *edge = [CXEdgeDetector sharedDetector];
    CXBokehRenderer *bokeh = [CXBokehRenderer sharedRenderer];
    CXSubjectTracker *tracker = [CXSubjectTracker sharedTracker];
    CXRackFocus *rack = [CXRackFocus sharedRackFocus];

    // Provide the active camera device to Rack Focus.
    AVCaptureDevice *dev = [self valueForKey:@"_videoCaptureDevice"];
    [rack setDevice:dev];

    // Frame tracking
    static CGRect prevBox = {};

    [tracker processFrame:original completion:^(CGRect box, BOOL needsReseg) {
        if (!CGRectEqualToRect(prevBox, CGRectZero) && !CGRectEqualToRect(box, CGRectZero)) {
            [rack evaluateRack:prevBox newBox:box];
        }
        prevBox = box;
    }];

    // Get current video image
    CVImageBufferRef imgBuf = CMSampleBufferGetImageBuffer(original);
    if (!imgBuf) return original;
    CIImage *frame = [CIImage imageWithCVPixelBuffer:imgBuf];

    // Kick the heavy Neural Engine segmentation onto a background queue (non-blocking).
    // It self-throttles, so the capture thread never waits on Vision.
    [edge submitFrame:imgBuf];

    // Use whatever mask is currently ready. On the first few frames this is nil
    // (no segmentation has completed yet) — skip blur until a mask exists.
    CIImage *latestMask = [edge latestMaskImage];
    if (!latestMask) return original;

    // Pull the latest disparity map (nil if depth isn't being delivered on this session).
    // When present, the renderer uses real depth blur; otherwise it falls back to the mask.
    CIImage *depthImage = [[CXDepthEngine sharedEngine] latestDepthImage];

    // Render Bokeh
    CIImage *result = [bokeh renderBokehForImage:frame
                                        withMask:latestMask
                                           depth:depthImage
                                       intensity:gBlurIntensity];

    if (!result) return original;

    // Render into a SEPARATE scratch buffer — never read and write imgBuf in one pass.
    // The scratch buffer is reused across frames and only (re)created if the frame
    // geometry/format changes. Both this render and the copy-back run synchronously
    // on the capture thread, so a single static buffer is safe (no concurrent access).
    static CVPixelBufferRef scratch = NULL;
    static size_t scratchW = 0, scratchH = 0;
    static OSType scratchFmt = 0;

    size_t w = CVPixelBufferGetWidth(imgBuf);
    size_t h = CVPixelBufferGetHeight(imgBuf);
    OSType fmt = CVPixelBufferGetPixelFormatType(imgBuf);

    if (!scratch || scratchW != w || scratchH != h || scratchFmt != fmt) {
        if (scratch) { CVPixelBufferRelease(scratch); scratch = NULL; }
        NSDictionary *attrs = @{
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
            (id)kCVPixelBufferMetalCompatibilityKey: @YES,
        };
        CVReturn cr = CVPixelBufferCreate(kCFAllocatorDefault, w, h, fmt,
                                          (__bridge CFDictionaryRef)attrs, &scratch);
        if (cr != kCVReturnSuccess || !scratch) { scratch = NULL; return original; }
        scratchW = w; scratchH = h; scratchFmt = fmt;
    }

    // 1) bokeh result (derived from imgBuf) -> scratch
    [bokeh.context render:result toCVPixelBuffer:scratch];
    // 2) scratch -> imgBuf (plain memory copy; no CoreImage read of imgBuf here)
    CXCopyPixelBuffer(scratch, imgBuf);

    return original;
}

%end
