#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <MetalKit/MetalKit.h>

extern BOOL gCinematicEnabled;
extern CGFloat gBlurIntensity;

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
- (CIImage *)latestMaskImage;
@end

@interface CXDepthEngine : NSObject
+ (instancetype)sharedEngine;
- (CIImage *)latestDepthImage;
@end

@interface CXLivePreviewView : UIView <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) AVCaptureSession *weakSession;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
+ (instancetype)sharedView;
- (void)attachToSession:(AVCaptureSession *)session;
- (void)hideNativePreview:(UIView *)camPreviewView;
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
        self.userInteractionEnabled = NO; // Let touches pass through
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
    
    // Create and add our data output to grab frames
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.videoOutput.alwaysDiscardsLateVideoFrames = YES;
    self.videoOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    
    dispatch_queue_t queue = dispatch_queue_create("com.cinematicx.preview", NULL);
    [self.videoOutput setSampleBufferDelegate:self queue:queue];
    
    if ([session canAddOutput:self.videoOutput]) {
        [session addOutput:self.videoOutput];
        NSLog(@"[CinematicX] Attached live preview data output to session");
    }
}

- (void)hideNativePreview:(UIView *)camPreviewView {
    // We will place ourselves on top, and if cinematic is on, we show our metal view
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (!gCinematicEnabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.metalView.hidden = YES;
        });
        return;
    }
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return;
    
    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
    
    // Apply blur using the existing logic
    CIImage *mask = [[NSClassFromString(@"CXEdgeDetector") sharedDetector] latestMaskImage];
    CIImage *depth = [[NSClassFromString(@"CXDepthEngine") sharedEngine] latestDepthImage];
    
    CIImage *resultImage = sourceImage;
    if (mask) {
        CIImage *blurred = [[NSClassFromString(@"CXBokehRenderer") sharedRenderer] renderBokehForImage:sourceImage withMask:mask depth:depth intensity:gBlurIntensity];
        if (blurred) {
            resultImage = blurred;
        }
    }
    
    // Correct orientation for preview (usually 90 degrees rotated depending on connection)
    // Assume portrait for now
    resultImage = [resultImage imageByApplyingTransform:CGAffineTransformMakeRotation(-M_PI_2)];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.metalView.hidden = NO;
        id<CAMetalDrawable> drawable = [self.metalView currentDrawable];
        if (drawable) {
            id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
            
            // Scale to fit
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
