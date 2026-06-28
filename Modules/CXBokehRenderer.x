#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>

// Blur intensity (gBlurIntensity) is a 0..1 slider value.
static const CGFloat kMaxBlurRadius = 22.0f; // Gaussian radius at intensity = 1.0
static const CGFloat kMinFStop      = 1.0f;  // intensity 1.0 -> shallow DoF, aggressive blur
static const CGFloat kMaxFStop      = 16.0f; // intensity 0.0 -> deep DoF, minimal blur

@interface CXBokehRenderer : NSObject
@property (nonatomic, strong) CIContext *context;
@property (nonatomic, strong) CIFilter *blurFilter;
@property (nonatomic, strong) CIFilter *bokehFilter;
@property (nonatomic, strong) CIFilter *blendFilter;
+ (instancetype)sharedRenderer;
- (CIImage *)renderBokehForImage:(CIImage *)inputImage withMask:(CIImage *)maskImage intensity:(CGFloat)intensity;
- (CIImage *)renderBokehForImage:(CIImage *)inputImage
                        withMask:(CIImage *)maskImage
                           depth:(CIImage *)depthImage
                       intensity:(CGFloat)intensity;
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
        _bokehFilter = [CIFilter filterWithName:@"CIBokehBlur"];
        _blendFilter = [CIFilter filterWithName:@"CIBlendWithMask"];
    }
    return self;
}

// Sets a CIFilter key only if the filter actually declares it, inside a guard.
// CIDepthBlurEffect is a semi-private filter whose key set varies by iOS version,
// and setValue:forUndefinedKey: would otherwise throw NSUnknownKeyException.
static void CXSetIfSupported(CIFilter *filter, id value, NSString *key) {
    if (!value || ![filter.inputKeys containsObject:key]) return;
    @try { [filter setValue:value forKey:key]; }
    @catch (__unused NSException *e) {}
}

// Back-compat entry point — no depth available.
- (CIImage *)renderBokehForImage:(CIImage *)inputImage withMask:(CIImage *)maskImage intensity:(CGFloat)intensity {
    return [self renderBokehForImage:inputImage withMask:maskImage depth:nil intensity:intensity];
}

- (CIImage *)renderBokehForImage:(CIImage *)inputImage
                        withMask:(CIImage *)maskImage
                           depth:(CIImage *)depthImage
                       intensity:(CGFloat)intensity {
    if (!inputImage) return inputImage;

    // Clamp the slider value to a sane 0..1 range.
    CGFloat t = MAX(0.0, MIN(1.0, intensity));

    // Primary path: real depth-based blur — physically realistic, uses the 3D disparity
    // map from CXDepthEngine instead of a flat background blur.
    if (depthImage) {
        // Map intensity 0..1 to an f-stop: low intensity = high f-stop (sharp/deep),
        // high intensity = low f-stop (shallow DoF / aggressive bokeh).
        CGFloat fStop = kMaxFStop - t * (kMaxFStop - kMinFStop);
        CIFilter *depthBlur = [CIFilter filterWithName:@"CIDepthBlurEffect"];
        if (depthBlur) {
            CXSetIfSupported(depthBlur, inputImage, kCIInputImageKey);
            CXSetIfSupported(depthBlur, depthImage, @"inputDisparityImage");
            CXSetIfSupported(depthBlur, maskImage,  @"inputMaskImage");
            CXSetIfSupported(depthBlur, @(fStop),   @"inputAperture");
            CIImage *result = depthBlur.outputImage;
            if (result) return result;
        }
        // fall through to the mask path if depth blur produced nothing
    }

    // Fallback path (no usable depth): blur the background, then composite the sharp
    // subject back on top via the Neural Engine mask. Requires a mask to know what to keep.
    if (!maskImage) return inputImage;

    // Map intensity 0..1 linearly to blur radius. At 0 the slider yields no blur;
    // at 1 it reaches the maximum cinematic radius.
    CGFloat blurRadius = t * kMaxBlurRadius;
    if (blurRadius < 0.5) return inputImage; // negligible blur -> leave frame sharp

    CIImage *blurredBackground = nil;

    // Prefer CIBokehBlur — it renders disc-shaped highlights ("bokeh balls") for a real
    // out-of-focus look, unlike CIGaussianBlur which just smears. CIBokehBlur expands the
    // extent, so clamp-to-edge first and crop back to the original frame afterward.
    if (self.bokehFilter) {
        CIImage *clamped = [inputImage imageByClampingToExtent];
        [self.bokehFilter setValue:clamped forKey:kCIInputImageKey];
        CXSetIfSupported(self.bokehFilter, @(blurRadius), kCIInputRadiusKey);
        CXSetIfSupported(self.bokehFilter, @(0.2),        @"inputRingAmount");
        CXSetIfSupported(self.bokehFilter, @(1.0),        @"inputSoftness");
        CIImage *out = self.bokehFilter.outputImage;
        if (out) blurredBackground = [out imageByCroppingToRect:inputImage.extent];
    }

    // Secondary fallback: plain Gaussian if CIBokehBlur is unavailable / produced nothing.
    if (!blurredBackground) {
        [self.blurFilter setValue:inputImage forKey:kCIInputImageKey];
        [self.blurFilter setValue:@(blurRadius) forKey:kCIInputRadiusKey];
        CIImage *out = self.blurFilter.outputImage;
        blurredBackground = out ? [out imageByCroppingToRect:inputImage.extent] : nil;
    }

    if (!blurredBackground) return inputImage;

    [self.blendFilter setValue:inputImage forKey:kCIInputImageKey];
    [self.blendFilter setValue:blurredBackground forKey:kCIInputBackgroundImageKey];
    [self.blendFilter setValue:maskImage forKey:kCIInputMaskImageKey];

    return self.blendFilter.outputImage;
}

@end
