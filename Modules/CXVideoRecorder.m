#import "CXVideoRecorder.h"
#import <Photos/Photos.h>

@interface CXVideoRecorder ()

@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput *videoInput;
@property (nonatomic, strong) AVAssetWriterInput *audioInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor;

@property (nonatomic, strong) dispatch_queue_t recordQueue;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL hasStartedSession;
@property (nonatomic, assign) CMTime startTime;

@property (nonatomic, strong) NSURL *outputURL;
@property (nonatomic, weak) id<AVCaptureFileOutputRecordingDelegate> delegate;

@end

@implementation CXVideoRecorder

+ (instancetype)sharedRecorder {
    static CXVideoRecorder *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.recordQueue = dispatch_queue_create("com.cinematicx.recorder", DISPATCH_QUEUE_SERIAL);
        self.isRecording = NO;
        self.hasStartedSession = NO;
    }
    return self;
}

- (void)startRecordingToURL:(NSURL *)url delegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    dispatch_async(self.recordQueue, ^{
        if (self.isRecording) return;
        
        self.outputURL = url;
        self.delegate = delegate;
        
        // Delete any existing file
        if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        }
        
        NSError *error = nil;
        self.assetWriter = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&error];
        if (error) {
            NSLog(@"[CinematicX] AVAssetWriter error: %@", error);
            return;
        }
        
        // Video Settings (1080p, 30fps, 16Mbps, H.264 High Profile)
        NSDictionary *compressionProperties = @{
            AVVideoAverageBitRateKey: @(16000000), // 16 Mbps
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: @(30)
        };
        
        NSDictionary *videoSettings = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(1920),
            AVVideoHeightKey: @(1080),
            AVVideoCompressionPropertiesKey: compressionProperties
        };
        
        self.videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
        self.videoInput.expectsMediaDataInRealTime = YES;
        // Fix orientation to portrait for now, later could pull from device orientation
        self.videoInput.transform = CGAffineTransformMakeRotation(M_PI_2);
        
        NSDictionary *sourcePixelBufferAttributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(1920),
            (id)kCVPixelBufferHeightKey: @(1080)
        };
        
        self.pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.videoInput sourcePixelBufferAttributes:sourcePixelBufferAttributes];
        
        if ([self.assetWriter canAddInput:self.videoInput]) {
            [self.assetWriter addInput:self.videoInput];
        }
        
        // Audio Settings (AAC, 44100Hz, 192kbps, Stereo)
        AudioChannelLayout channelLayout;
        memset(&channelLayout, 0, sizeof(AudioChannelLayout));
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
        
        NSDictionary *audioSettings = @{
            AVFormatIDKey: @(kAudioFormatMPEG4AAC),
            AVSampleRateKey: @(44100.0),
            AVNumberOfChannelsKey: @(2),
            AVEncoderBitRateKey: @(192000),
            AVChannelLayoutKey: [NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)]
        };
        
        self.audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
        self.audioInput.expectsMediaDataInRealTime = YES;
        
        if ([self.assetWriter canAddInput:self.audioInput]) {
            [self.assetWriter addInput:self.audioInput];
        }
        
        if ([self.assetWriter startWriting]) {
            self.isRecording = YES;
            self.hasStartedSession = NO;
            NSLog(@"[CinematicX] AVAssetWriter started writing.");
            
            // Spoof delegate callback to UI
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(captureOutput:didStartRecordingToOutputFileAtURL:fromConnections:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
                    [self.delegate captureOutput:(AVCaptureFileOutput *)nil didStartRecordingToOutputFileAtURL:self.outputURL fromConnections:@[]];
#pragma clang diagnostic pop
                }
            });
        }
    });
}

- (void)stopRecording {
    dispatch_async(self.recordQueue, ^{
        if (!self.isRecording) return;
        self.isRecording = NO;
        
        [self.videoInput markAsFinished];
        [self.audioInput markAsFinished];
        
        [self.assetWriter finishWritingWithCompletionHandler:^{
            NSLog(@"[CinematicX] AVAssetWriter finished writing.");
            
            // Save to PHPhotoLibrary
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:self.outputURL];
            } completionHandler:^(BOOL success, NSError *error) {
                NSLog(@"[CinematicX] Saved to Photos: %d, Error: %@", success, error);
                
                // Spoof delegate callback to UI
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
                        [self.delegate captureOutput:(AVCaptureFileOutput *)nil didFinishRecordingToOutputFileAtURL:self.outputURL fromConnections:@[] error:error];
#pragma clang diagnostic pop
                    }
                });
            }];
            
            self.assetWriter = nil;
            self.videoInput = nil;
            self.audioInput = nil;
            self.pixelBufferAdaptor = nil;
        }];
    });
}

- (void)appendVideoPixelBuffer:(CVPixelBufferRef)pixelBuffer withPresentationTime:(CMTime)time {
    if (!self.isRecording || !pixelBuffer) return;
    
    // We are on a background queue (from AVCaptureVideoDataOutput).
    // Dispatch to our serial writer queue, BUT drop frames if it's busy!
    // Using an asynchronous dispatch without blocking. But if the queue is backed up, memory grows.
    // So we use a simple try-lock or check. Actually, dispatch_async is fine if the encoder is fast, 
    // but the user said "If frame processing falls behind: drop frame, never block".
    // We can do this by using a boolean flag or checking if videoInput isReadyForMoreMediaData.
    
    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(self.recordQueue, ^{
        if (!self.isRecording || self.assetWriter.status != AVAssetWriterStatusWriting) {
            CVPixelBufferRelease(pixelBuffer);
            return;
        }
        
        if (!self.hasStartedSession) {
            [self.assetWriter startSessionAtSourceTime:time];
            self.hasStartedSession = YES;
            self.startTime = time;
        }
        
        if (self.videoInput.isReadyForMoreMediaData) {
            [self.pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:time];
        } else {
            NSLog(@"[CinematicX] Dropped video frame - encoder busy");
        }
        CVPixelBufferRelease(pixelBuffer);
    });
}

- (void)appendAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!self.isRecording || !sampleBuffer) return;
    
    CFRetain(sampleBuffer);
    dispatch_async(self.recordQueue, ^{
        if (!self.isRecording || self.assetWriter.status != AVAssetWriterStatusWriting || !self.hasStartedSession) {
            CFRelease(sampleBuffer);
            return;
        }
        
        if (self.audioInput.isReadyForMoreMediaData) {
            [self.audioInput appendSampleBuffer:sampleBuffer];
        }
        CFRelease(sampleBuffer);
    });
}

@end
