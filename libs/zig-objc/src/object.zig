const std = @import("std");
const c = @import("c.zig");
const objc = @import("main.zig");
const MsgSend = @import("msg_send.zig").MsgSend;

/// Object is an instance of a class.
pub const Object = struct {
    value: c.id,

    pub usingnamespace MsgSend(Object);

    /// Convert a raw "id" into an Object. id must fit the size of the
    /// normal C "id" type (i.e. a `usize`).
    pub fn fromId(id: anytype) Object {
        return .{ .value = @ptrCast(@alignCast(@alignOf(id))) };
    }

    /// Returns the class of an object.
    pub fn getClass(self: Object) ?objc.Class {
        return objc.Class{
            .value = c.object_getClass(self.value) orelse return null,
        };
    }

    /// Returns the class name of a given object.
    pub fn getClassName(self: Object) [:0]const u8 {
        return std.mem.sliceTo(c.object_getClassName(self.value), 0);
    }

    /// Set a property. This is a helper around getProperty and is
    /// strictly less performant than doing it manually. Consider doing
    /// this manually if performance is critical.
    pub fn setProperty(self: Object, comptime n: [:0]const u8, v: anytype) void {
        const Class = self.getClass().?;
        const setter = setter: {
            // See getProperty for why we do this.
            if (Class.getProperty(n)) |prop| {
                if (prop.copyAttributeValue("S")) |val| {
                    defer objc.free(val);
                    break :setter objc.sel(val);
                }
            }

            break :setter objc.sel(
                "set" ++
                    [1]u8{std.ascii.toUpper(n[0])} ++
                    n[1..n.len] ++
                    ":",
            );
        };

        self.msgSend(void, setter, .{v});
    }

    /// Get a property. This is a helper around Class.getProperty and is
    /// strictly less performant than doing it manually. Consider doing
    /// this manually if performance is critical.
    pub fn getProperty(self: Object, comptime T: type, comptime n: [:0]const u8) T {
        const Class = self.getClass().?;
        const getter = getter: {
            // Sometimes a property is not a property because it has been
            // overloaded or something. I've found numerous occasions the
            // Apple docs are just wrong, so we try to read it as a property
            // but if we can't then we just call it as-is.
            if (Class.getProperty(n)) |prop| {
                if (prop.copyAttributeValue("G")) |val| {
                    defer objc.free(val);
                    break :getter objc.sel(val);
                }
            }

            break :getter objc.sel(n);
        };

        return self.msgSend(T, getter, .{});
    }
};

test {
    const testing = std.testing;
    const NSObject = objc.Class.getClass("NSObject").?;

    // Should work with our wrappers
    const obj = NSObject.msgSend(objc.Object, objc.Sel.registerName("alloc"), .{});
    try testing.expect(obj.value != null);
    try testing.expectEqualStrings("NSObject", obj.getClassName());
    obj.msgSend(void, objc.sel("dealloc"), .{});
}
