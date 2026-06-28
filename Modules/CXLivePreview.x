#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <MetalKit/MetalKit.h>

extern BOOL gCinematicEnabled;
extern CGFloat gBlurIntensity;

#import "CXVideoRecorder.h"

// Forward declare to access the custom renderer from Tweak.x
@interface CXBokehRenderer : NSObject
+ (instancetype)sharedRenderer;
- (CIImage *)renderBokehForImage:(CIImage *)inputImage
                        withMask:(CIImage *)maskImage
                           depth:(CIImage *)depthImage
                       intensity:(CGFloat)intensity;
@property (nonatomic, strong) CIContext *context;
@end

@interface CXEdgeDetector : NSObject
+ (instancetype)sharedDetector;
- (void)submitFrame:(CVPixelBufferRef)pixelBuffer;
- (CIImage *)latestMaskImage;
@end

@interface CXDepthEngine : NSObject
+ (instancetype)sharedEngine;
- (CIImage *)latestDepthImage;
@end

@interface CXLivePreviewView : UIView <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) AVCaptureSession *weakSession;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
+ (instancetype)sharedView;
- (void)attachToSession:(AVCaptureSession *)session;
@end

@implementation CXLivePreviewView

+ (instancetype)sharedView {
    static CXLivePreviewView *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] initWithFrame:[UIScreen mainScreen].bounds];
    });
    return shared;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        self.metalView = [[MTKView alloc] initWithFrame:self.bounds device:device];
        self.metalView.framebufferOnly = NO;
        self.metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.metalView.userInteractionEnabled = NO;
        self.metalView.hidden = YES;
        [self addSubview:self.metalView];
        
        self.commandQueue = [device newCommandQueue];
        self.ciContext = [CIContext contextWithMTLDevice:device options:@{kCIContextWorkingColorSpace: [NSNull null]}];
    }
    return self;
}

- (void)attachToSession:(AVCaptureSession *)session {
    if (self.weakSession == session) return;
    self.weakSession = session;
    
    dispatch_queue_t queue = dispatch_queue_create("com.cinematicx.preview", NULL);
    
    // Video Output
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.videoOutput.alwaysDiscardsLateVideoFrames = YES;
    self.videoOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    [self.videoOutput setSampleBufferDelegate:self queue:queue];
    
    if ([session canAddOutput:self.videoOutput]) {
        [session addOutput:self.videoOutput];
    }
    
    // Audio Output
    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.audioOutput setSampleBufferDelegate:self queue:queue];
    
    if ([session canAddOutput:self.audioOutput]) {
        [session addOutput:self.audioOutput];
    }
    
    NSLog(@"[CinematicX] Attached live preview data output and audio output to session");
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    // Handle Audio
    if (output == self.audioOutput) {
        if (gCinematicEnabled) {
            [[NSClassFromString(@"CXVideoRecorder") sharedRecorder] appendAudioSampleBuffer:sampleBuffer];
        }
        return;
    }
    
    // Handle Video
    if (!gCinematicEnabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.metalView.hidden = YES;
        });
        return;
    }
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return;
    
    [[NSClassFromString(@"CXEdgeDetector") sharedDetector] submitFrame:imageBuffer];
    
    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
    CIImage *mask = [[NSClassFromString(@"CXEdgeDetector") sharedDetector] latestMaskImage];
    CIImage *depth = [[NSClassFromString(@"CXDepthEngine") sharedEngine] latestDepthImage];
    
    CIImage *resultImage = sourceImage;
    if (mask) {
        CIImage *blurred = [[NSClassFromString(@"CXBokehRenderer") sharedRenderer] renderBokehForImage:sourceImage withMask:mask depth:depth intensity:gBlurIntensity];
        if (blurred) {
            resultImage = blurred;
        }
    }
    
    // Pipe the blurred frame to the Video Recorder
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    // Create a new CVPixelBuffer to hold the blurred image for the recorder
    CVPixelBufferRef renderBuffer = NULL;
    NSDictionary *options = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &renderBuffer);
    
    if (renderBuffer) {
        // We need to render the blurred CIImage into a buffer.
        // It should match 1080p for the asset writer.
        CGFloat scaleX = 1920.0 / resultImage.extent.size.width;
        CGFloat scaleY = 1080.0 / resultImage.extent.size.height;
        CGFloat renderScale = MAX(scaleX, scaleY);
        CIImage *scaledForRender = [resultImage imageByApplyingTransform:CGAffineTransformMakeScale(renderScale, renderScale)];
        
        [self.ciContext render:scaledForRender toCVPixelBuffer:renderBuffer];
        [[NSClassFromString(@"CXVideoRecorder") sharedRecorder] appendVideoPixelBuffer:renderBuffer withPresentationTime:timestamp];
        CVPixelBufferRelease(renderBuffer);
    }
    
    // Draw to Live Preview MTKView
    resultImage = [resultImage imageByApplyingTransform:CGAffineTransformMakeRotation(-M_PI_2)];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.metalView.hidden = NO;
        id<CAMetalDrawable> drawable = [self.metalView currentDrawable];
        if (drawable) {
            id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
            CGFloat scaleX = self.metalView.drawableSize.width / resultImage.extent.size.width;
            CGFloat scaleY = self.metalView.drawableSize.height / resultImage.extent.size.height;
            CGFloat scale = MAX(scaleX, scaleY);
            CIImage *scaledImage = [resultImage imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
            [self.ciContext render:scaledImage toMTLTexture:drawable.texture commandBuffer:commandBuffer bounds:scaledImage.extent colorSpace:CGColorSpaceCreateDeviceRGB()];
            [commandBuffer presentDrawable:drawable];
            [commandBuffer commit];
        }
    });
}
@end

// Hook AVCaptureSession to attach our preview layer
%hook AVCaptureSession
- (void)startRunning {
    %orig;
    [[CXLivePreviewView sharedView] attachToSession:self];
}
%end

// Hook CAMViewfinderView to place our preview view
@interface CAMViewfinderView : UIView
@end
%hook CAMViewfinderView
- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        CXLivePreviewView *preview = [CXLivePreviewView sharedView];
        [preview removeFromSuperview];
        preview.frame = self.bounds;
        [self addSubview:preview];
        [self bringSubviewToFront:preview];
    }
}
%end

// Hijack AVCaptureMovieFileOutput
%hook AVCaptureMovieFileOutput
- (void)startRecordingToOutputFileURL:(NSURL *)outputFileURL recordingDelegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    if (gCinematicEnabled) {
        NSLog(@"[CinematicX] Hijacking native record start!");
        [[NSClassFromString(@"CXVideoRecorder") sharedRecorder] startRecordingToURL:outputFileURL delegate:delegate];
    } else {
        %orig;
    }
}
- (void)stopRecording {
    if (gCinematicEnabled) {
        NSLog(@"[CinematicX] Hijacking native record stop!");
        [[NSClassFromString(@"CXVideoRecorder") sharedRecorder] stopRecording];
    } else {
        %orig;
    }
}
%end
