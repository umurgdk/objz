#import <Foundation/Foundation.h>
#include <objc/NSObjCRuntime.h>

typedef NS_OPTIONS(NSUInteger, MTLBlitOption) {
  MTLBlitOptionNone = 0,
  MTLBlitOptionDepthFromDepthStencil = 1 << 0,
  MTLBlitOptionStencilFromDepthStencil = 1 << 1,
  MTLBlitOptionRowLinearPVRTC API_AVAILABLE(ios(9.0), macos(11.0),
                                            macCatalyst(14.0)) = 1 << 2,
} API_AVAILABLE(macos(10.11), ios(9.0));

typedef NS_ENUM(NSInteger, MTLCommandEncoderErrorState) {
  MTLCommandEncoderErrorStateUnknown = 0,
  MTLCommandEncoderErrorStateCompleted = 1,
  MTLCommandEncoderErrorStateAffected = 2,
  MTLCommandEncoderErrorStatePending = 3,
  MTLCommandEncoderErrorStateFaulted = 4,
} API_AVAILABLE(macos(11.0), ios(14.0));

NS_ASSUME_NONNULL_BEGIN
@protocol SomeProtocol <NSObject>
- (void)someMethod:(id<NSObject>)anObject;
@end

@interface AnotherClass : NSObject
- (void)blit:(MTLBlitOption)options;
@end

@interface MyClass : AnotherClass <SomeProtocol>

@property NSString *name;
@property NSUInteger age;

+ (instancetype)factory;
- (instancetype)initWithName:(NSString *)name andInt:(NSUInteger)age;
- (int)primitiveMethod:(int)count;
- (id<SomeProtocol>)instanceMethod:
    (NSDictionary<AnotherClass *, NSString *> *)name;

@end
NS_ASSUME_NONNULL_END