#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@interface PLCameraController : NSObject
@property (nonatomic, assign) CGFloat videoZoomFactor;
@property (nonatomic, assign) BOOL portraitEffectsMatteEnabled;
@property (nonatomic, assign) BOOL depthDataDeliveryEnabled;
@property (nonatomic, strong) AVCaptureDevice *videoCaptureDevice;
@property (nonatomic, strong) AVCaptureSession *captureSession;
- (void)_configureFocusAndExposure;
- (void)switchToCamera:(NSInteger)position;
- (CMSampleBufferRef)_processedSampleBuffer:(CMSampleBufferRef)buffer;
- (void)startVideoCapture;
- (void)stopVideoCapture;
@end

@interface PLCameraView : UIView
@property (nonatomic, strong) PLCameraController *cameraController;
@end
