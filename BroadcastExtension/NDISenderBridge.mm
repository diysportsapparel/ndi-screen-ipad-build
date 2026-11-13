#import "NDISenderBridge.h"

#import <CoreImage/CoreImage.h>
#import <Processing.NDI.Lib.h>
#import <QuartzCore/QuartzCore.h>
#import <ReplayKit/ReplayKit.h>
#import <os/log.h>

#include <cmath>
#include <string>

@interface NDISenderBridge () {
    NDIlib_send_instance_t _sender;
    NSInteger _width;
    NSInteger _height;
    NSInteger _fps;
    std::string _name;
    CIContext *_ciContext;
    CVPixelBufferPoolRef _pixelBufferPool;
    CGColorSpaceRef _colorSpace;
    CFTimeInterval _lastVideoWallTime;
    BOOL _ndiInitialized;
}
@end

@implementation NDISenderBridge

- (nullable instancetype)initWithName:(NSString *)name
                               width:(NSInteger)width
                              height:(NSInteger)height
                                 fps:(NSInteger)fps {
    self = [super init];
    if (!self) {
        return nil;
    }

    if (name.length == 0 || width < 2 || height < 2 || fps <= 0) {
        return nil;
    }

    _sender = NULL;
    _width = width;
    _height = height;
    _fps = fps;
    _name = name.UTF8String;
    _lastVideoWallTime = 0;

    if (!NDIlib_initialize()) {
        os_log_error(OS_LOG_DEFAULT, "NDI initialize failed");
        return nil;
    }
    _ndiInitialized = YES;

    NDIlib_send_create_t sendDescription = {};
    sendDescription.p_ndi_name = _name.c_str();
    sendDescription.p_groups = NULL;
    sendDescription.clock_video = true;
    sendDescription.clock_audio = false;

    _sender = NDIlib_send_create(&sendDescription);
    if (!_sender) {
        os_log_error(OS_LOG_DEFAULT, "NDI sender creation failed");
        [self stop];
        return nil;
    }

    _colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    _ciContext = [CIContext contextWithOptions:@{
        kCIContextUseSoftwareRenderer: @NO,
        kCIContextCacheIntermediates: @NO
    }];

    NSDictionary *poolAttributes = @{
        (id)kCVPixelBufferPoolMinimumBufferCountKey: @2
    };
    NSDictionary *pixelBufferAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(_width),
        (id)kCVPixelBufferHeightKey: @(_height),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };

    CVReturn poolStatus = CVPixelBufferPoolCreate(
        kCFAllocatorDefault,
        (__bridge CFDictionaryRef)poolAttributes,
        (__bridge CFDictionaryRef)pixelBufferAttributes,
        &_pixelBufferPool
    );

    if (poolStatus != kCVReturnSuccess) {
        os_log_error(OS_LOG_DEFAULT, "Pixel buffer pool creation failed: %d", poolStatus);
        [self stop];
        return nil;
    }

    os_log_info(
        OS_LOG_DEFAULT,
        "NDI sender started: %{public}@, %ldx%ld @ %ld fps",
        name,
        (long)_width,
        (long)_height,
        (long)_fps
    );

    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)isRunning {
    return _sender != NULL;
}

- (void)sendVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!_sender || !sampleBuffer) {
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval minimumInterval = (1.0 / (double)_fps) - 0.002;
    if (_lastVideoWallTime > 0 && (now - _lastVideoWallTime) < minimumInterval) {
        return;
    }
    _lastVideoWallTime = now;

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) {
        return;
    }

    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)imageBuffer;
    CGImagePropertyOrientation orientation = [self orientationForSampleBuffer:sampleBuffer];
    BOOL canSendDirectly =
        CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA &&
        orientation == kCGImagePropertyOrientationUp &&
        CVPixelBufferGetWidth(pixelBuffer) == (size_t)_width &&
        CVPixelBufferGetHeight(pixelBuffer) == (size_t)_height;

    NDIlib_video_frame_v2_t videoFrame = {};
    videoFrame.xres = (int)_width;
    videoFrame.yres = (int)_height;
    videoFrame.FourCC = NDIlib_FourCC_type_BGRA;
    videoFrame.frame_rate_N = (int)_fps;
    videoFrame.frame_rate_D = 1;
    videoFrame.picture_aspect_ratio = (float)_width / (float)_height;
    videoFrame.frame_format_type = NDIlib_frame_format_type_progressive;
    videoFrame.timecode = 0;
    // NDI generates the send-side timestamp; this field is receive-only.
    videoFrame.timestamp = 0;
    videoFrame.p_metadata = NULL;

    if (canSendDirectly) {
        CVReturn lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        if (lockStatus != kCVReturnSuccess) {
            return;
        }

        videoFrame.p_data = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
        videoFrame.line_stride_in_bytes = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
        NDIlib_send_send_video_v2(_sender, &videoFrame);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return;
    }

    CVPixelBufferRef convertedBuffer = NULL;
    CVReturn bufferStatus = CVPixelBufferPoolCreatePixelBuffer(
        kCFAllocatorDefault,
        _pixelBufferPool,
        &convertedBuffer
    );
    if (bufferStatus != kCVReturnSuccess || !convertedBuffer) {
        return;
    }

    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:pixelBuffer options:@{
        kCIImageColorSpace: (__bridge id)_colorSpace
    }];
    CIImage *orientedImage = [sourceImage imageByApplyingCGOrientation:orientation];
    CGRect extent = orientedImage.extent;
    if (extent.size.width <= 0 || extent.size.height <= 0) {
        CVPixelBufferRelease(convertedBuffer);
        return;
    }

    CGFloat scale = MIN(
        (CGFloat)_width / extent.size.width,
        (CGFloat)_height / extent.size.height
    );
    CIImage *scaledImage = [orientedImage imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CGRect scaledExtent = scaledImage.extent;
    CGAffineTransform centering = CGAffineTransformMakeTranslation(
        (((CGFloat)_width - scaledExtent.size.width) * 0.5) - scaledExtent.origin.x,
        (((CGFloat)_height - scaledExtent.size.height) * 0.5) - scaledExtent.origin.y
    );
    CIImage *centeredImage = [scaledImage imageByApplyingTransform:centering];
    CIImage *blackBackground = [CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:1]];
    CIImage *compositedImage = [centeredImage imageByCompositingOverImage:blackBackground];

    [_ciContext render:compositedImage
       toCVPixelBuffer:convertedBuffer
                bounds:CGRectMake(0, 0, _width, _height)
            colorSpace:_colorSpace];

    CVReturn lockStatus = CVPixelBufferLockBaseAddress(convertedBuffer, kCVPixelBufferLock_ReadOnly);
    if (lockStatus == kCVReturnSuccess) {
        videoFrame.p_data = (uint8_t *)CVPixelBufferGetBaseAddress(convertedBuffer);
        videoFrame.line_stride_in_bytes = (int)CVPixelBufferGetBytesPerRow(convertedBuffer);
        NDIlib_send_send_video_v2(_sender, &videoFrame);
        CVPixelBufferUnlockBaseAddress(convertedBuffer, kCVPixelBufferLock_ReadOnly);
    }

    CVPixelBufferRelease(convertedBuffer);
}

- (void)sendAudioPCMBuffer:(AVAudioPCMBuffer *)buffer timestamp:(CMTime)timestamp {
    if (!_sender || !buffer || buffer.frameLength == 0) {
        return;
    }

    if (buffer.format.isInterleaved || !buffer.floatChannelData) {
        return;
    }

    NDIlib_audio_frame_v3_t audioFrame = {};
    audioFrame.sample_rate = (int)buffer.format.sampleRate;
    audioFrame.no_channels = (int)buffer.format.channelCount;
    audioFrame.no_samples = (int)buffer.frameLength;
    audioFrame.timecode = 0;
    audioFrame.FourCC = NDIlib_FourCC_audio_type_FLTP;
    // NDI expects the distance between planar channel starts. The
    // AVAudioPCMBuffer stride can be frameCapacity rather than frameLength.
    audioFrame.channel_stride_in_bytes =
        (int)(buffer.frameLength * sizeof(float));
    audioFrame.p_data = (uint8_t *)buffer.floatChannelData[0];
    audioFrame.p_metadata = NULL;
    // NDI generates the send-side timestamp; this field is receive-only.
    audioFrame.timestamp = 0;

    NDIlib_send_send_audio_v3(_sender, &audioFrame);
}

- (void)stop {
    @synchronized (self) {
        if (_sender) {
            NDIlib_send_destroy(_sender);
            _sender = NULL;
        }

        if (_pixelBufferPool) {
            CVPixelBufferPoolRelease(_pixelBufferPool);
            _pixelBufferPool = NULL;
        }

        if (_colorSpace) {
            CGColorSpaceRelease(_colorSpace);
            _colorSpace = NULL;
        }

        if (_ndiInitialized) {
            NDIlib_destroy();
            _ndiInitialized = NO;
        }
    }
}

- (CGImagePropertyOrientation)orientationForSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CFTypeRef value = CMGetAttachment(
        sampleBuffer,
        (__bridge CFStringRef)RPVideoSampleOrientationKey,
        NULL
    );
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
        return (CGImagePropertyOrientation)[(__bridge NSNumber *)value integerValue];
    }
    return kCGImagePropertyOrientationUp;
}

- (int64_t)ndiTimestampForSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    return [self ndiTimestampForCMTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
}

- (int64_t)ndiTimestampForCMTime:(CMTime)time {
    if (CMTIME_IS_VALID(time)) {
        double seconds = CMTimeGetSeconds(time);
        if (std::isfinite(seconds)) {
            return (int64_t)(seconds * 10000000.0);
        }
    }
    return (int64_t)(CACurrentMediaTime() * 10000000.0);
}

@end

