#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>

@interface CXDepthEngine : NSObject <AVCaptureDepthDataOutputDelegate>
@property (nonatomic, strong) AVCaptureDepthDataOutput *depthOutput;
@property (nonatomic, assign) CVPixelBufferRef latestDepthMap; // retained; guarded by @synchronized(self)
@property (nonatomic, assign) CMTime latestDepthTimestamp;
@property (nonatomic, strong) dispatch_queue_t depthQueue;
+ (instancetype)sharedEngine;
- (void)attachToSession:(AVCaptureSession *)session;
- (BOOL)isDepthAvailable;
- (CIImage *)latestDepthImage; // thread-safe snapshot for the render pipeline
@end

@implementation CXDepthEngine

+ (instancetype)sharedEngine {
    static CXDepthEngine *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _depthQueue = dispatch_queue_create("com.afaq.cx.depth", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)attachToSession:(AVCaptureSession *)session {
    if (!session) return;

    // Safety check 0: Exclude Photo presets to prevent Portrait mode crashes
    if ([session.sessionPreset isEqualToString:AVCaptureSessionPresetPhoto]) {
        NSLog(@"[CinematicX] Session is a photo preset. Skipping depth attachment.");
        return;
    }

    // Safety check 1: Only attach to a session whose video input device can actually
    // deliver depth. This is the real fix for the "attach to every session" crash —
    // audio-only, metadata, or non-depth-capable sessions are skipped entirely.
    BOOL depthCapable = NO;
    for (AVCaptureInput *input in session.inputs) {
        if (![input isKindOfClass:[AVCaptureDeviceInput class]]) continue;
        AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
        if (device.activeFormat.supportedDepthDataFormats.count > 0) {
            depthCapable = YES;
            break;
        }
    }
    if (!depthCapable) {
        NSLog(@"[CinematicX] No depth-capable video input on this session. Skipping.");
        return;
    }

    // Safety check 2: Don't add if a depth output already exists (ours or the camera's)
    for (AVCaptureOutput *output in session.outputs) {
        if ([output isKindOfClass:[AVCaptureDepthDataOutput class]]) {
            NSLog(@"[CinematicX] Session already has a depth output, skipping attachment.");
            return;
        }
    }

    // Reconfiguring a live session can throw (NSInvalidArgumentException) on format
    // mismatches — guard it so a failure degrades gracefully instead of crashing Camera.
    @try {
        [session beginConfiguration];
        AVCaptureDepthDataOutput *output = [[AVCaptureDepthDataOutput alloc] init];
        output.filteringEnabled = YES;
        output.alwaysDiscardsLateDepthData = NO;
        if ([session canAddOutput:output]) {
            [session addOutput:output];
            [output setDelegate:self callbackQueue:self.depthQueue];
            self.depthOutput = output;
            NSLog(@"[CinematicX] Depth output attached");
        } else {
            NSLog(@"[CinematicX] Depth output rejected by session");
        }
        [session commitConfiguration];
    } @catch (NSException *e) {
        NSLog(@"[CinematicX] Depth attach exception: %@", e);
        // Balance the open beginConfiguration; ignore any secondary failure.
        @try { [session commitConfiguration]; } @catch (__unused NSException *e2) {}
        self.depthOutput = nil;
    }
}

- (void)depthDataOutput:(AVCaptureDepthDataOutput *)output
       didOutputDepthData:(AVDepthData *)depthData
              timestamp:(CMTime)timestamp
             connection:(AVCaptureConnection *)connection {
    if (!depthData) return;

    // Only convert when the incoming type isn't already disparity-float32.
    // depthDataByConvertingToDepthDataType: throws on unsupported source types,
    // so guard it — a bad frame must not crash the camera.
    AVDepthData *depth = depthData;
    if (depthData.depthDataType != kCVPixelFormatType_DisparityFloat32) {
        @try {
            depth = [depthData depthDataByConvertingToDepthDataType:kCVPixelFormatType_DisparityFloat32];
        } @catch (NSException *e) {
            NSLog(@"[CinematicX] Depth conversion failed: %@", e);
            return;
        }
    }

    CVPixelBufferRef buf = depth.depthDataMap;
    if (!buf) return;
    CVPixelBufferRetain(buf);
    @synchronized (self) {
        if (_latestDepthMap) CVPixelBufferRelease(_latestDepthMap);
        _latestDepthMap = buf;
        _latestDepthTimestamp = timestamp;
    }
}

- (BOOL)isDepthAvailable {
    @synchronized (self) { return _latestDepthMap != NULL; }
}

// CIImage retains the backing buffer for its own lifetime, so the snapshot stays
// valid even if the depth queue swaps the cache right after we return.
- (CIImage *)latestDepthImage {
    @synchronized (self) {
        if (!_latestDepthMap) return nil;
        return [CIImage imageWithCVPixelBuffer:_latestDepthMap];
    }
}

- (void)dealloc {
    @synchronized (self) {
        if (_latestDepthMap) CVPixelBufferRelease(_latestDepthMap);
    }
}

@end

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    [[CXDepthEngine sharedEngine] attachToSession:self];
}

- (void)addOutput:(AVCaptureOutput *)output {
    // Safety check 2: If the Camera app tries to add its own depth output (like in Portrait mode),
    // we MUST remove ours first to prevent a multiple-depth-outputs crash.
    if ([output isKindOfClass:[AVCaptureDepthDataOutput class]]) {
        CXDepthEngine *engine = [CXDepthEngine sharedEngine];
        if (engine.depthOutput && output != engine.depthOutput) {
            NSLog(@"[CinematicX] Camera app is adding its own depth output. Removing ours to prevent crash.");
            [self removeOutput:engine.depthOutput];
            engine.depthOutput = nil;
        }
    }
    %orig;
}
%end

%hook AVCapturePhotoSettings
- (void)setDepthDataDeliveryEnabled:(BOOL)e { %orig(YES); }
- (void)setPortraitEffectsMatteDeliveryEnabled:(BOOL)e { %orig(YES); }
%end
