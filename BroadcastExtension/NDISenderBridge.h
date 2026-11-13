#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NDISenderBridge : NSObject

- (nullable instancetype)initWithName:(NSString *)name
                               width:(NSInteger)width
                              height:(NSInteger)height
                                 fps:(NSInteger)fps NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)sendVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;

- (void)sendAudioPCMBuffer:(AVAudioPCMBuffer *)buffer
                 timestamp:(CMTime)timestamp;

- (void)stop;

@property(nonatomic, readonly, getter=isRunning) BOOL running;

@end

NS_ASSUME_NONNULL_END

