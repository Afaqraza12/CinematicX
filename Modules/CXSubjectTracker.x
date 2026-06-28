#import <Vision/Vision.h>

static const CGFloat kMinConfidence = 0.40f;
static const NSInteger kResegInterval = 15;

@interface CXSubjectTracker : NSObject
@property (nonatomic, strong) VNSequenceRequestHandler *handler;
@property (nonatomic, strong) VNDetectedObjectObservation *currentObs;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, assign) CGRect lastBox;
@property (nonatomic, assign) BOOL tracking;
+ (instancetype)sharedTracker;
- (void)processFrame:(CMSampleBufferRef)buf
          completion:(void(^)(CGRect box, BOOL needsReseg))cb;
- (void)resetWith:(VNDetectedObjectObservation *)obs;
@end

@implementation CXSubjectTracker

+ (instancetype)sharedTracker {
    static CXSubjectTracker *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _handler = [[VNSequenceRequestHandler alloc] init];
        _frameCount = 0;
        _tracking = NO;
    }
    return self;
}

- (void)processFrame:(CMSampleBufferRef)buf
          completion:(void(^)(CGRect, BOOL))cb {
    self.frameCount++;
    BOOL periodicReseg = (self.frameCount % kResegInterval == 0);

    // (Re)acquire a subject when we have nothing to track, or on the periodic refresh.
    // This is the bootstrap the tracker was missing — without it, VNTrackObjectRequest
    // never had a seed observation, so tracking never engaged and no box was ever produced.
    if (!self.tracking || !self.currentObs || periodicReseg) {
        VNDetectedObjectObservation *detected = [self detectSubjectIn:buf];
        if (detected) {
            self.currentObs = detected;
            self.lastBox = detected.boundingBox;
            self.tracking = YES;
            if (cb) cb(detected.boundingBox, YES); // new subject → mask needs a full reseg
        } else {
            self.tracking = NO;
            if (cb) cb(CGRectZero, YES);
        }
        return;
    }

    // Cheap frame-to-frame tracking now that we have a seed observation.
    VNTrackObjectRequest *req =
        [[VNTrackObjectRequest alloc] initWithDetectedObjectObservation:self.currentObs];
    req.trackingLevel = VNRequestTrackingLevelAccurate;

    NSError *err;
    [self.handler performRequests:@[req] onCMSampleBuffer:buf error:&err];
    if (err) { self.tracking = NO; if (cb) cb(self.lastBox, YES); return; }

    VNDetectedObjectObservation *res = req.results.firstObject;
    if (!res || res.confidence < kMinConfidence) {
        self.tracking = NO;          // lost the subject → next frame re-detects
        if (cb) cb(self.lastBox, YES);
        return;
    }

    self.currentObs = res;
    self.lastBox = res.boundingBox;
    if (cb) cb(res.boundingBox, NO);
}

// One-shot person detection used to seed/refresh the tracker. Picks the largest
// detected person so we lock onto the dominant subject in frame.
- (VNDetectedObjectObservation *)detectSubjectIn:(CMSampleBufferRef)buf {
    CVImageBufferRef img = CMSampleBufferGetImageBuffer(buf);
    if (!img) return nil;

    VNDetectHumanRectanglesRequest *req = [[VNDetectHumanRectanglesRequest alloc] init];
    VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc] initWithCVPixelBuffer:img options:@{}];

    NSError *err;
    [handler performRequests:@[req] error:&err];
    if (err) return nil;

    VNDetectedObjectObservation *best = nil;
    CGFloat bestArea = 0;
    for (VNDetectedObjectObservation *o in req.results) {
        CGFloat area = o.boundingBox.size.width * o.boundingBox.size.height;
        if (area > bestArea) { bestArea = area; best = o; }
    }
    return best;
}

- (void)resetWith:(VNDetectedObjectObservation *)obs {
    self.currentObs = obs;
    self.tracking = YES;
    self.frameCount = 0;
    NSLog(@"[CinematicX] Tracker reset");
}

@end
