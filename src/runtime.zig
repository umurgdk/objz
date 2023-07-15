const std = @import("std");
const trait = std.meta.trait;
const objc = @import("objc");

pub usingnamespace @import("runtime/Id.zig");
pub const NSObject = @import("runtime/NSObject.zig");
pub const NSString = @import("runtime/NSString.zig");

pub const isInstanceType = trait.multiTrait(.{
    trait.hasField("__object"),
    trait.hasFn("__call"),
});

pub const Class = objc.Class;
