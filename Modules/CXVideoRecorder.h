#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface CXVideoRecorder : NSObject

@property (nonatomic, assign, readonly) BOOL isRecording;

+ (instancetype)sharedRecorder;

- (void)startRecordingToURL:(NSURL *)url delegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate;
- (void)stopRecording;

// Feed frames from CXLivePreview
- (void)appendVideoPixelBuffer:(CVPixelBufferRef)pixelBuffer withPresentationTime:(CMTime)time;
- (void)appendAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end
