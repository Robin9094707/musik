#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Narrow Objective-C boundary to the audio engine and TagLib-backed metadata.
@interface SMAudioEngine : NSObject
@property(nonatomic, copy, nullable) void (^onEnd)(void);
@property(nonatomic, copy, nullable) void (^onError)(NSString *message);
@property(nonatomic, copy, nullable) void (^onState)(BOOL playing);
@property(nonatomic, readonly) double time;
@property(nonatomic, readonly) double duration;
@property(nonatomic, readonly) BOOL playing;
- (BOOL)startURL:(NSURL *)url error:(NSError **)error NS_SWIFT_NAME(startURL(_:));
- (void)pause;
- (BOOL)resume:(NSError **)error NS_SWIFT_NAME(resume());
- (void)stop;
- (BOOL)seek:(double)seconds;
@end
@interface SMTags : NSObject
+ (nullable NSDictionary<NSString *, id> *)readURL:(NSURL *)url error:(NSError **)error NS_SWIFT_NAME(readURL(_:));
+ (BOOL)writeURL:(NSURL *)url values:(NSDictionary<NSString *, id> *)values error:(NSError **)error NS_SWIFT_NAME(writeURL(_:values:));
+ (BOOL)validateURL:(NSURL *)url error:(NSError **)error NS_SWIFT_NAME(validateURL(_:));
+ (NSArray<NSString *> *)extensions;
@end
NS_ASSUME_NONNULL_END
