#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

@interface CXEdgeDetector : NSObject
@property (nonatomic, strong) VNSequenceRequestHandler *requestHandler;
@property (nonatomic, strong) dispatch_queue_t segmentationQueue;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) CVPixelBufferRef cachedMask; // retained; protected by @synchronized(self)
+ (instancetype)sharedDetector;
- (void)submitFrame:(CVPixelBufferRef)pixelBuffer; // async, never blocks the caller
- (CIImage *)latestMaskImage;                      // thread-safe snapshot of the newest mask
@end

@implementation CXEdgeDetector

+ (instancetype)sharedDetector {
    static CXEdgeDetector *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // VNSequenceRequestHandler is highly optimized for processing consecutive video frames
        _requestHandler = [[VNSequenceRequestHandler alloc] init];
        // Dedicated serial queue keeps Vision/Neural Engine work OFF the capture thread
        _segmentationQueue = dispatch_queue_create("com.afaq.cx.segmentation", DISPATCH_QUEUE_SERIAL);
        _busy = NO;
        _cachedMask = NULL;
    }
    return self;
}

// Called from the capture thread once per frame. Returns immediately.
// If a segmentation pass is already in flight we drop this frame (self-throttling)
// so requests never pile up and stall the pipeline.
- (void)submitFrame:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) return;
    @synchronized (self) {
        if (self.busy) return;
        self.busy = YES;
    }

    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(self.segmentationQueue, ^{
        VNGeneratePersonSegmentationRequest *request = [[VNGeneratePersonSegmentationRequest alloc] init];
        // Use Fast mode because the A11 Neural Engine (iPhone X) often fails on Accurate
        request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelFast;
        request.outputPixelFormat = kCVPixelFormatType_OneComponent32Float;

        NSError *error = nil;
        [self.requestHandler performRequests:@[request] onCVPixelBuffer:pixelBuffer error:&error];
        CVPixelBufferRelease(pixelBuffer);

        VNPixelBufferObservation *observation = request.results.firstObject;
        if (error || !observation) {
            NSLog(@"[CinematicX] Edge detection failed: %@", error);
            @synchronized (self) { self.busy = NO; }
            return;
        }

        // Retain the mask so it outlives the request scope, then swap it into the cache.
        CVPixelBufferRef newMask = observation.pixelBuffer;
        CVPixelBufferRetain(newMask);
        @synchronized (self) {
            if (self.cachedMask) CVPixelBufferRelease(self.cachedMask);
            self.cachedMask = newMask;
            self.busy = NO;
        }
    });
}

// Capture-thread read. CIImage retains the underlying buffer for its own lifetime,
// so the snapshot stays valid even if the background queue swaps the cache afterward.
- (CIImage *)latestMaskImage {
    @synchronized (self) {
        if (!self.cachedMask) return nil;
        return [CIImage imageWithCVPixelBuffer:self.cachedMask];
    }
}

- (void)dealloc {
    if (_cachedMask) CVPixelBufferRelease(_cachedMask);
}

@end
