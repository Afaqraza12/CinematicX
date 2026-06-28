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
    if (self.frameCount % kResegInterval == 0 || !self.tracking) {
        if (cb) cb(self.lastBox, YES);
        return;
    }
    if (!self.currentObs) { if (cb) cb(CGRectZero, YES); return; }

    VNTrackObjectRequest *req =
        [[VNTrackObjectRequest alloc] initWithDetectedObjectObservation:self.currentObs];
    req.trackingLevel = VNRequestTrackingLevelAccurate;

    NSError *err;
    [self.handler performRequests:@[req] onCMSampleBuffer:buf error:&err];
    if (err) { if (cb) cb(self.lastBox, YES); return; }

    VNDetectedObjectObservation *res = req.results.firstObject;
    if (!res || res.confidence < kMinConfidence) {
        self.tracking = NO;
        if (cb) cb(self.lastBox, YES);
        return;
    }

    self.currentObs = res;
    self.lastBox = res.boundingBox;
    if (cb) cb(res.boundingBox, NO);
}

- (void)resetWith:(VNDetectedObjectObservation *)obs {
    self.currentObs = obs;
    self.tracking = YES;
    self.frameCount = 0;
    NSLog(@"[CinematicX] Tracker reset");
}

@end
