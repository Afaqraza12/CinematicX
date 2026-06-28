#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

@interface CXEdgeDetector : NSObject
@property (nonatomic, strong) VNSequenceRequestHandler *requestHandler;
+ (instancetype)sharedDetector;
- (CIImage *)refinedMaskFromPixelBuffer:(CVPixelBufferRef)pixelBuffer;
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
    }
    return self;
}

- (CIImage *)refinedMaskFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) return nil;
    
    // Create the person segmentation request
    VNGeneratePersonSegmentationRequest *request = [[VNGeneratePersonSegmentationRequest alloc] init];
    
    // Accurate mode uses the A11 Neural Engine for highly detailed hair/edge cutouts
    request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;
    request.outputPixelFormat = kCVPixelFormatType_OneComponent32Float;
    
    NSError *error = nil;
    // Perform the request on the current video frame
    [self.requestHandler performRequests:@[request] onCVPixelBuffer:pixelBuffer error:&error];
    
    if (error || !request.results.firstObject) {
        NSLog(@"[CinematicX] Edge detection failed: %@", error);
        return nil;
    }
    
    VNPixelBufferObservation *observation = request.results.firstObject;
    
    // Convert the resulting pixel buffer mask into a CIImage for rendering later
    return [CIImage imageWithCVPixelBuffer:observation.pixelBuffer];
}

@end
