#import <AVFoundation/AVFoundation.h>

@interface CXDepthEngine : NSObject <AVCaptureDepthDataOutputDelegate>
@property (nonatomic, strong) AVCaptureDepthDataOutput *depthOutput;
@property (nonatomic, assign) CVPixelBufferRef latestDepthMap;
@property (nonatomic, assign) CMTime latestDepthTimestamp;
@property (nonatomic, strong) dispatch_queue_t depthQueue;
+ (instancetype)sharedEngine;
- (void)attachToSession:(AVCaptureSession *)session;
- (BOOL)isDepthAvailable;
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
    [session beginConfiguration];
    self.depthOutput = [[AVCaptureDepthDataOutput alloc] init];
    self.depthOutput.filteringEnabled = YES;
    self.depthOutput.alwaysDiscardsLateDepthData = NO;
    if ([session canAddOutput:self.depthOutput]) {
        [session addOutput:self.depthOutput];
        [self.depthOutput setDelegate:self callbackQueue:self.depthQueue];
        NSLog(@"[CinematicX] Depth output attached");
    } else {
        NSLog(@"[CinematicX] Depth output rejected by session");
    }
    [session commitConfiguration];
}

- (void)depthDataOutput:(AVCaptureDepthDataOutput *)output
       didOutputDepthData:(AVDepthData *)depthData
              timestamp:(CMTime)timestamp
             connection:(AVCaptureConnection *)connection {
    AVDepthData *converted = [depthData
        depthDataByConvertingToDepthDataType:kCVPixelFormatType_DisparityFloat32];
    CVPixelBufferRef buf = converted.depthDataMap;
    CVPixelBufferRetain(buf);
    if (self.latestDepthMap) CVPixelBufferRelease(self.latestDepthMap);
    self.latestDepthMap = buf;
    self.latestDepthTimestamp = timestamp;
}

- (BOOL)isDepthAvailable { return self.latestDepthMap != NULL; }

@end

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    [[CXDepthEngine sharedEngine] attachToSession:self];
}
%end

%hook AVCapturePhotoSettings
- (void)setDepthDataDeliveryEnabled:(BOOL)e { %orig(YES); }
- (void)setPortraitEffectsMatteDeliveryEnabled:(BOOL)e { %orig(YES); }
%end
