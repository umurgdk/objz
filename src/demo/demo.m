#include "demo.h"
#include <Foundation/Foundation.h>
#include <objc/NSObjCRuntime.h>

@implementation AnotherClass

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

- (id<NSObject>)someMethod:(id<NSObject>)anObject {
  return self;
}

@end