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

typedef struct {
    void (* name)(int age, float);
} FnPointers;

NS_ASSUME_NONNULL_BEGIN

@protocol SomeProtocol <NSObject>
- (void)someMethod:(id<NSObject>)anObject;
@end

@interface Generic<__covariant A, __covariant B> : NSObject
@property (copy, readwrite) A a;
@property (copy, readwrite) B b;

- (void)method:(const A <SomeProtocol> _Nonnull [_Nullable])arg;
- (void)dynArray:(const NSUInteger [_Nullable])arg;
@end

@interface AnotherClass : NSObject
- (void)blit:(MTLBlitOption)options;
- (instancetype)init;
@end

@interface MyClass : AnotherClass <SomeProtocol>

@property (copy, nonatomic, readwrite) NSString *name;
@property (nonatomic, readwrite) NSUInteger age;
@property (nonatomic, readwrite) NSUInteger (*callback)(NSUInteger num);

+ (instancetype)factory;
- (instancetype)initWithName:(NSString *)name andInt:(NSUInteger)age;
- (int)primitiveMethod:(int)count;
- (NSUInteger)runCallback:(NSUInteger)num;
- (id<SomeProtocol>)instanceMethod:
    (NSDictionary<AnotherClass *, NSString *> *)name;

@end
NS_ASSUME_NONNULL_END

typedef struct {
    /**
     * @brief Instance options
     */
    MTLBlitOption options;

    /**
     * @brief Instance mask used to ignore geometry during ray tracing
     */
    uint32_t mask;

    /**
     * @brief Motion border mode describing what happens if acceleration structure is sampled
     * before motionStartTime
     */
    MTLCommandEncoderErrorState motionStartBorderMode;

    /**
     * @brief Motion end time of this instance
     */
    float motionEndTime;
} MTLAccelerationStructureMotionInstanceDescriptor API_AVAILABLE(macos(12.0), ios(15.0));