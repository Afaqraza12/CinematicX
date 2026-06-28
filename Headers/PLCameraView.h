#import <UIKit/UIKit.h>

@class PLCameraController;

// Top-level view of Apple's Camera app preview/controls hierarchy.
// CinematicX injects its overlay into this view's hierarchy.
@interface PLCameraView : UIView
@property (nonatomic, strong) PLCameraController *cameraController;
@end
