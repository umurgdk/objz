const std = @import("std");
const objc = @import("objc");
const sel = objc.sel;

const Self = @This();
pub const __class_name = "NSString";
var __class: ?objc.Class = null;

pub const conforms_to = .{};

pub const Encoding = enum(c_uint) {
    utf8 = 4,
};

pub const Instance = struct {
    __object: objc.Object,

    pub inline fn init(self: Instance) Instance {
        self.call(Instance, "init", .{});
    }

    pub inline fn cStringUsingEncoding(self: Instance, encoding: Encoding) []const u8 {
        const str = self.__call([*c]const u8, sel("cStringUsingEncoding:"), .{@intFromEnum(encoding)});
        const bytes_len = self.lengthOfBytesUsingEncoding(encoding);
        return str[0..bytes_len];
    }

    pub inline fn lengthOfBytesUsingEncoding(self: Instance, encoding: Encoding) u32 {
        return self.__call(u32, sel("lengthOfBytesUsingEncoding:"), .{@intFromEnum(encoding)});
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

pub inline fn allocStaticStr(comptime bytes: []const u8) Instance {
    const self = alloc();
    return self.__call(Instance, objc.sel("initWithBytesNoCopy:length:encoding:freeWhenDone:"), .{
        bytes.ptr,
        bytes.len,
        4,
        false,
    });
}

pub inline fn allocStr(bytes: []const u8) Instance {
    return __call(Instance, objc.sel("stringWithCString:encoding:"), .{bytes.ptr});
}

pub inline fn __call(comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
    if (ReturnType == Instance) {
        const instance = class().msgSend(objc.Object, selector, args);
        return Instance{ .__object = instance };
    } else {
        return class().msgSend(ReturnType, selector, args);
    }
}
