#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>

// --- Interface Declarations to satisfy compiler ---
@interface CXDepthEngine : NSObject
@property (nonatomic, assign) CVPixelBufferRef latestDepthMap;
+ (instancetype)sharedEngine;
@end

@interface CXEdgeDetector : NSObject
+ (instancetype)sharedDetector;
- (CIImage *)refinedMaskFromPixelBuffer:(CVPixelBufferRef)pixelBuffer;
@end

@interface CXBokehRenderer : NSObject
@property (nonatomic, strong) CIContext *context;
+ (instancetype)sharedRenderer;
- (CIImage *)renderBokehForImage:(CIImage *)inputImage withMask:(CIImage *)maskImage aperture:(CGFloat)aperture;
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

// --- Main Pipeline ---

%hook PLCameraController

- (CMSampleBufferRef)_processedSampleBuffer:(CMSampleBufferRef)buffer {
    CMSampleBufferRef original = %orig(buffer);
    
    // Fast path: skip processing entirely if Cinematic Mode is toggled off
    if (!gCinematicEnabled) return original;

    CXEdgeDetector *edge = [CXEdgeDetector sharedDetector];
    CXBokehRenderer *bokeh = [CXBokehRenderer sharedRenderer];
    CXSubjectTracker *tracker = [CXSubjectTracker sharedTracker];
    CXRackFocus *rack = [CXRackFocus sharedRackFocus];

    // Provide the active camera device to Rack Focus
    AVCaptureDevice *dev = [self valueForKey:@"_videoCaptureDevice"];
    [rack setDevice:dev];

    // Frame tracking & Mask Generation
    static CGRect prevBox = {};
    static CIImage *latestMask = nil; // Cache the mask across frames
    
    [tracker processFrame:original completion:^(CGRect box, BOOL needsReseg) {
        if (!CGRectEqualToRect(prevBox, CGRectZero) && !CGRectEqualToRect(box, CGRectZero)) {
            [rack evaluateRack:prevBox newBox:box];
        }
        prevBox = box;

        if (needsReseg) {
            // Re-run the heavy Neural Engine Edge Detector if tracking lost
            CVImageBufferRef imgBuf = CMSampleBufferGetImageBuffer(original);
            if (imgBuf) {
                latestMask = [edge refinedMaskFromPixelBuffer:imgBuf];
            }
        }
    }];

    // Get current video image
    CVImageBufferRef imgBuf = CMSampleBufferGetImageBuffer(original);
    if (!imgBuf) return original;
    CIImage *frame = [CIImage imageWithCVPixelBuffer:imgBuf];

    // Render Bokeh
    // Note: We use the Neural Engine mask (latestMask) for the cutout instead of the raw depth map
    CIImage *result = [bokeh renderBokehForImage:frame withMask:latestMask aperture:gBlurIntensity];

    if (!result) return original;

    // Overwrite the original pixel buffer with our cinematic blurred result!
    [bokeh.context render:result toCVPixelBuffer:imgBuf];

    return original;
}

%end
