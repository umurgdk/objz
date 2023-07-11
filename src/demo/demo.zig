const objz = @import("objz");
const objc = @import("objc");
const sel = objc.sel;

const NSString = objz.NSString;
const NSDictionary = objz.NSDictionary;

pub const SomeProtocol = struct {
    const __protocol_name = "SomeProtocol";

    pub fn InstanceMethods(comptime Instance: type) type {
        return struct {
            pub inline fn someMethod(self: Instance, anObject__: Id(NSObject)) Id(NSObject) {
                return self.__call(Id(NSObject), sel("someMethod:"), .{anObject__});
            }
        };
    }
};

pub const AnotherClass = struct {
    const Self = @This();
    pub const __class_name = "AnotherClass";
    var __class: ?objc.Class = null;

    pub const conforms_to = .{};

    pub const Instance = struct {
        __object: objc.Object,

        pub fn __call(self: Self, comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
            if (ReturnType == Self) {
                const instance = self.__object.msgSend(objc.Object, selector, args);
                return Self{ .__object = instance };
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
        if (ReturnType == Instance) {
            const instance = class().msgSend(objc.Object, selector, args);
            return Instance{ .object = instance };
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
        __object: objc.Object,

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
        pub fn __call(self: Self, comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
            if (ReturnType == Self) {
                const instance = self.__object.msgSend(objc.Object, selector, args);
                return Self{ .__object = instance };
            } else {
                return self.__object.msgSend(ReturnType, selector, args);
            }
        }
    };

    pub inline fn factory() Instance {
        return __call(Instance, sel("factory"), .{});
    }

    pub inline fn myClassWithNameAndInt(name__: *NSString.Instance, age__: i32) i32 {
        return __call(i32, sel("myClassWithName:andInt:"), .{ name__, age__ });
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
        if (ReturnType == Instance) {
            const instance = class().msgSend(objc.Object, selector, args);
            return Instance{ .object = instance };
        } else {
            return class().msgSend(ReturnType, selector, args);
        }
    }
};
