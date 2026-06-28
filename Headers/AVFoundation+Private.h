// AVFoundation+Private.h
// Private/SPI surface of AVFoundation used by CinematicX. These declarations let us
// reference symbols the public SDK hides, without dragging in the whole private framework.

#import <AVFoundation/AVFoundation.h>

@interface AVCaptureDevice (CinematicXPrivate)
// Some builds expose finer-grained zoom ramp controls than the public header.
- (void)rampToVideoZoomFactor:(CGFloat)factor withRate:(float)rate;
- (void)cancelVideoZoomRamp;
@end

@interface AVCaptureSession (CinematicXPrivate)
@property (nonatomic, readonly) NSArray<AVCaptureOutput *> *outputs;
@property (nonatomic, readonly) NSArray<AVCaptureInput *> *inputs;
@end

// Disparity/depth pixel format constant aliases, in case the SDK in use predates them.
#ifndef kCVPixelFormatType_DisparityFloat32
#define kCVPixelFormatType_DisparityFloat32 'fdep'
#endif
