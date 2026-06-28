#import <AVFoundation/AVFoundation.h>

@interface CAMCaptureEngine : NSObject
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDevice *activeCamera;
- (void)setZoomFactor:(CGFloat)factor animated:(BOOL)animated;
- (void)enableDepthDataOutput:(BOOL)enable;
- (AVCaptureConnection *)videoConnection;
@end
