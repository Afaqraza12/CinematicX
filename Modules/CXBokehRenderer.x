#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>

@interface CXBokehRenderer : NSObject
@property (nonatomic, strong) CIContext *context;
@property (nonatomic, strong) CIFilter *blurFilter;
@property (nonatomic, strong) CIFilter *blendFilter;
+ (instancetype)sharedRenderer;
- (CIImage *)renderBokehForImage:(CIImage *)inputImage withMask:(CIImage *)maskImage aperture:(CGFloat)aperture;
@end

@implementation CXBokehRenderer

+ (instancetype)sharedRenderer {
    static CXBokehRenderer *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Use Metal for highly optimized hardware-accelerated rendering on the GPU
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        _context = [CIContext contextWithMTLDevice:device options:@{
            kCIContextWorkingColorSpace: [NSNull null],
            kCIContextUseSoftwareRenderer: @NO
        }];
        
        _blurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
        _blendFilter = [CIFilter filterWithName:@"CIBlendWithMask"];
    }
    return self;
}

- (CIImage *)renderBokehForImage:(CIImage *)inputImage withMask:(CIImage *)maskImage aperture:(CGFloat)aperture {
    if (!inputImage || !maskImage) return inputImage;
    
    // 1. Calculate blur radius from aperture (e.g. f/1.4 -> high blur, f/16 -> low blur)
    CGFloat maxAperture = 16.0;
    CGFloat blurRadius = MAX(1.0, (maxAperture - aperture) * 2.0);
    
    // 2. Blur the entire background using Gaussian Blur
    [self.blurFilter setValue:inputImage forKey:kCIInputImageKey];
    [self.blurFilter setValue:@(blurRadius) forKey:kCIInputRadiusKey];
    CIImage *blurredBackground = self.blurFilter.outputImage;
    
    // 3. Blend the sharp input image over the blurred background using the Neural Engine mask
    [self.blendFilter setValue:inputImage forKey:kCIInputImageKey];
    [self.blendFilter setValue:blurredBackground forKey:kCIInputBackgroundImageKey];
    [self.blendFilter setValue:maskImage forKey:kCIInputMaskImageKey];
    
    return self.blendFilter.outputImage;
}

@end
