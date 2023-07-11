const std = @import("std");
const clang = @import("clang.zig");

pub const Env = struct {
    out_file: std.fs.File,
    process_dir_path: []const u8,
    remove_prefix: []const u8,
    allocator: std.mem.Allocator,
};

pub const Argument = struct {
    name: []const u8,
    typ: []const u8,
};

pub const Class = struct {
    name: []const u8,
    super: []const u8,
    protocols: []const []const u8,

    instance_methods: std.ArrayList(Method),
    class_methods: std.ArrayList(Method),

    pub fn init(name: []const u8, super: []const u8, protocols: []const []const u8, allocator: std.mem.Allocator) Class {
        return Class{
            .name = name,
            .super = super,
            .protocols = protocols,
            .instance_methods = std.ArrayList(Method).init(allocator),
            .class_methods = std.ArrayList(Method).init(allocator),
        };
    }
};

pub const Protocol = struct {
    name: []const u8,
    protocols: std.ArrayList([]const u8),

    instance_methods: std.ArrayList(Method),
    class_methods: std.ArrayList(Method),

    pub fn init(name: []const u8, allocator: std.mem.Allocator) Protocol {
        return Protocol{
            .name = name,
            .protocols = std.ArrayList([]const u8).init(allocator),
            .instance_methods = std.ArrayList(Method).init(allocator),
            .class_methods = std.ArrayList(Method).init(allocator),
        };
    }
};

pub const Method = struct {
    selector: []const u8,
    arguments: []const Argument,
    return_typ: []const u8,
    placement: enum { class, instance },

    pub fn fnName(m: Method, buf: []u8) anyerror![]const u8 {
        var fbs = std.io.fixedBufferStream(buf);
        const writer = fbs.writer();

        var sel_i: usize = 0;
        var sel_it = std.mem.tokenize(u8, m.selector, ":");
        while (sel_it.next()) |sel| : (sel_i += 1) {
            if (sel_i == 0) {
                try writer.writeByte(sel[0]);
            } else {
                try writer.writeByte(std.ascii.toUpper(sel[0]));
            }

            try writer.writeAll(sel[1..]);
        }

        return fbs.getWritten();
    }
};

pub fn clangTypeToZig(typ: clang.Type, fbs: *std.io.FixedBufferStream([]u8)) void {
    const writer = fbs.writer();

    var t = typ;

    if (t.isId()) {
        writer.writeAll("Id(") catch unreachable;

        var arg_i: usize = 0;
        var proto_it = t.protocols();
        while (proto_it.next()) |arg| : (arg_i += 1) {
            const spelling = arg.spelling();
            defer spelling.free();

            writer.writeAll(spelling.str()) catch unreachable;
            if (arg_i < proto_it.len - 1) writer.writeAll(", ") catch unreachable;
        }

        writer.writeAll(")") catch unreachable;
        return;
    } else if (t.isInstancetype()) {
        writer.writeAll("Instance") catch unreachable;
        return;
    } else if (t.pointerKind() == .object) {
        clangTypeToZig(t.pointee(), fbs);
        return;
    }

    if (t.isPointer()) {
        writer.writeAll("*") catch unreachable;
        clangTypeToZig(typ.pointee(), fbs);
        return;
    }

    if (t.isConst()) {
        writer.writeAll("const ") catch unreachable;
    }

    const name_string = t.spelling();
    defer name_string.free();

    var name = name_string.str();
    var args_it = t.args();

    if (args_it.len > 0) {
        if (std.mem.indexOf(u8, name, "<")) |langle_idx| {
            name = name[0..langle_idx];
        }
        writer.writeAll(name) catch unreachable;

        writer.writeAll("(") catch unreachable;

        var args_i: usize = 0;
        while (args_it.next()) |arg| : (args_i += 1) {
            clangTypeToZig(arg, fbs);
            if (args_i < args_it.len - 1) writer.writeAll(", ") catch unreachable;
        }

        writer.writeAll(").Instance") catch unreachable;
        return;
    } else if (t.isObject()) {
        writer.writeAll(name) catch unreachable;
        writer.writeAll(".Instance") catch unreachable;
        return;
    }

    writer.writeAll(switch (t.kind()) {
        .void => "void",
        .int => "i32",
        .char_s, .char_u, .uchar, .schar => "u8",
        .char16 => "u16",
        .char32 => "u32",
        .ushort => "u16",
        .uint => "u32",
        .ulong => "u32",
        .ulonglong => "u64",
        .uint128 => "u128",
        .float => "f32",
        .double => "f64",
        .float128 => "f128",
        .float16 => "f16",
        .elaborated => {
            return clangTypeToZig(t.named(), fbs);
        },
        .typedef => {
            return clangTypeToZig(t.typedefUnderlying(), fbs);
        },
        else => |k| {
            const spel = t.spelling();
            defer spel.free();
            std.debug.panic("Unknown c type: {}, spelling: {s}", .{ k, spel.str() });
        },
    }) catch unreachable;
}
