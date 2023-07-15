#include "demo.h"
#include <Foundation/Foundation.h>
#include <objc/NSObjCRuntime.h>

@implementation Generic
- (void)method:(id<SomeProtocol>  _Nonnull const * _Nullable)arg {
}

- (void)dynArray:(const NSUInteger * _Nonnull * _Nullable)arg {
}

@end

@implementation AnotherClass

- (instancetype)init {
  self = [super init];
  return self;
}

- (void)blit:(MTLBlitOption)options {
  NSLog(@"Blitting with options:");
  if (options & MTLBlitOptionDepthFromDepthStencil) {
    NSLog(@"depthFromDepthStencil");
  }

  if (options & MTLBlitOptionStencilFromDepthStencil) {
    NSLog(@"stencilFromDepthStencil");
  }
}

@end

@implementation MyClass

// @synthesize name;
// @synthesize age;

+ (instancetype)factory {
  MyClass *inst = [MyClass alloc];
  if (self) {
    inst = [super init];
  }
  return inst;
}

- (instancetype)initWithName:(NSString *)name andInt:(NSUInteger)age {
  self = [super init];
  if (self) {
    self.name = name;
    self.age = age;
  }

  return self;
}

- (int)primitiveMethod:(int)count {
  return count * count;
}

- (id<SomeProtocol>)instanceMethod:
    (NSDictionary<AnotherClass *, NSString *> *)name {
  return self;
}

- (void)someMethod:(id<NSObject>)anObject {

}

- (NSUInteger)runCallback:(NSUInteger)num {
  return self.callback(num);
}

@end