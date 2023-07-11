const objc = @import("objc");

pub fn NSDictionary(comptime Key: type, comptime Value: type) type {
    _ = Value;
    _ = Key;
    return struct {
        const Self = @This();
        pub const __class_name = "NSDictionary";
        var __class: ?objc.Class = null;

        pub const conforms_to = .{};

        pub const Instance = struct {
            __object: objc.Object,

            pub inline fn init(self: Instance) Instance {
                self.call(Instance, "init", .{});
            }

            pub inline fn __call(self: Instance, comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
                if (ReturnType == Instance) {
                    const instance = self.__object.msgSend(objc.Object, selector, args);
                    return Instance{ .__object = instance };
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
}
