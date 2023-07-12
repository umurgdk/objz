const objz = @import("objz");
const objc = @import("objc");
const sel = objc.sel;

const Id = objz.Id;
const NSObject = objz.NSObject;
const NSString = objz.NSString;
const NSDictionary = objz.NSDictionary;

pub const MTLBlitOption = struct {
    pub const Value = u32;
    pub const none = 0;
    pub const depthFromDepthStencil = 1;
    pub const stencilFromDepthStencil = 2;
    pub const rowLinearPVRTC = 4;
};

pub const MTLCommandEncoderErrorState = enum(i32) {
    unknown = 0,
    completed = 1,
    affected = 2,
    pending = 3,
    faulted = 4,
};

pub const SomeProtocol = struct {
    pub const conforms_to = .{
        NSObject,
    };
    const __protocol_name = "SomeProtocol";

    pub fn InstanceMethods(comptime Instance: type) type {
        return struct {
            pub inline fn someMethod(self: Instance, anObject__: Id(NSObject)) void {
                return self.__call(void, sel("someMethod:"), .{anObject__});
            }
        };
    }
};

pub const AnotherClass = struct {
    const Self = @This();
    pub const __class_name = "AnotherClass";
    var __class: ?objc.Class = null;

    pub const conforms_to = .{
    };

    pub const Instance = struct {
        pub const conforms_to = Self.conforms_to;
        __object: objc.Object,

        pub inline fn blit(self: Instance, options__: MTLBlitOption.Value) void {
            return self.__call(void, sel("blit:"), .{options__});
        }
        pub inline fn init(self: Instance) Instance {
            return self.__call(Instance, sel("init"), .{});
        }
        
        pub inline fn __call(self: Instance, comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
            if (comptime objz.isInstanceType(ReturnType)) {
                const instance = self.__object.msgSend(objc.Object, selector, args);
                return ReturnType{ .__object = instance };
            } else {
                return self.__object.msgSend(ReturnType, selector, args);
            }
        }
        
    };
    
    
    inline fn class() objc.Class {
        if (Self.__class) |cls| return cls;
        Self.__class = objc.Class.getClass(Self.__class_name).?;
        return Self.__class.?;
    }
    
    pub inline fn alloc() Instance {
        return __call(Instance, objc.sel("alloc"), .{});
    }
    
    pub inline fn __call(comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
        if (comptime objz.isInstanceType(ReturnType)) {
            const instance = class().msgSend(objc.Object, selector, args);
            return ReturnType{ .__object = instance };
        } else {
            return class().msgSend(ReturnType, selector, args);
        }
    }
    
    
};

pub const MyClass = struct {
    const Self = @This();
    pub const __class_name = "MyClass";
    var __class: ?objc.Class = null;

    pub const conforms_to = .{
        SomeProtocol,
    };

    pub const Instance = struct {
        pub const conforms_to = Self.conforms_to;
        __object: objc.Object,

        pub inline fn initWithNameAndInt(self: Instance, name__: NSString.Instance, age__: u32) Instance {
            return self.__call(Instance, sel("initWithName:andInt:"), .{name__, age__});
        }

        pub inline fn primitiveMethod(self: Instance, count__: i32) i32 {
            return self.__call(i32, sel("primitiveMethod:"), .{count__});
        }

        pub inline fn instanceMethod(self: Instance, name__: NSDictionary(AnotherClass.Instance, NSString.Instance).Instance) Id(SomeProtocol) {
            return self.__call(Id(SomeProtocol), sel("instanceMethod:"), .{name__});
        }

        pub inline fn name(self: Instance) NSString.Instance {
            return self.__call(NSString.Instance, sel("name"), .{});
        }

        pub inline fn setName(self: Instance, name__: NSString.Instance) void {
            return self.__call(void, sel("setName:"), .{name__});
        }

        pub inline fn age(self: Instance) u32 {
            return self.__call(u32, sel("age"), .{});
        }

        pub inline fn setAge(self: Instance, age__: u32) void {
            return self.__call(void, sel("setAge:"), .{age__});
        }
        pub inline fn init(self: Instance) Instance {
            return self.__call(Instance, sel("init"), .{});
        }
        
        pub inline fn __call(self: Instance, comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
            if (comptime objz.isInstanceType(ReturnType)) {
                const instance = self.__object.msgSend(objc.Object, selector, args);
                return ReturnType{ .__object = instance };
            } else {
                return self.__object.msgSend(ReturnType, selector, args);
            }
        }
        
    };
    
    pub inline fn factory() Instance {
        return __call(Instance, sel("factory"), .{});
    }
    
    inline fn class() objc.Class {
        if (Self.__class) |cls| return cls;
        Self.__class = objc.Class.getClass(Self.__class_name).?;
        return Self.__class.?;
    }
    
    pub inline fn alloc() Instance {
        return __call(Instance, objc.sel("alloc"), .{});
    }
    
    pub inline fn __call(comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
        if (comptime objz.isInstanceType(ReturnType)) {
            const instance = class().msgSend(objc.Object, selector, args);
            return ReturnType{ .__object = instance };
        } else {
            return class().msgSend(ReturnType, selector, args);
        }
    }
    
    
};

pub const MTLAccelerationStructureMotionInstanceDescriptor = extern struct {
    options: MTLBlitOption.Value,
    mask: u32,
    motionStartBorderMode: MTLCommandEncoderErrorState,
    motionEndTime: f32,
};

