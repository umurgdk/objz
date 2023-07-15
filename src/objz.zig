const std = @import("std");
const clang = @import("clang.zig");

var fmt_buf: [2048]u8 = undefined;

pub const Env = struct {
    out_file: std.fs.File,
    file_filter: []const u8,
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
    type_args: []const []const u8,

    instance_methods: std.ArrayList(Method),
    class_methods: std.ArrayList(Method),

    pub fn isGeneric(c: *const Class) bool {
        return c.type_args.len > 0;
    }

    pub fn init(
        name: []const u8,
        super: []const u8,
        protocols: []const []const u8,
        type_args: []const []const u8,
        allocator: std.mem.Allocator,
    ) Class {
        return Class{
            .name = name,
            .super = super,
            .protocols = protocols,
            .type_args = type_args,
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

pub fn Enum(comptime Value: type) type {
    return struct {
        pub const Case = struct { name: []const u8, value: Value };
        cases: []const Case,
        name: []const u8,
        typ: []const u8,
        is_options: bool,
    };
}

pub const Struct = struct {
    name: []const u8,
    fields: []const Field,

    pub const Field = struct {
        name: []const u8,
        typ: []const u8,
    };
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

pub fn clangTypeToZig(typ: clang.Type, fbs: *std.io.FixedBufferStream([]u8)) anyerror!void {
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
        writer.writeAll("Instance__") catch unreachable;
        return;
    } else if (t.pointerKind() == .object) {
        return clangTypeToZig(t.pointee(), fbs);
    }

    const is_pointer = t.isPointer();
    if (is_pointer) {
        writer.writeAll("*") catch unreachable;
        if (t.isConst()) {
            writer.writeAll("const ") catch unreachable;
        }

        return clangTypeToZig(typ.pointee(), fbs);
    }

    if (t.isConst()) {
        writer.writeAll("const ") catch unreachable;
    }

    if (t.isNullable()) {
        std.log.debug("Found nullable", .{});
    }

    const name_string = t.spelling();
    defer name_string.free();

    var name = name_string.str();
    var args_it = t.args();

    if (args_it.len > 0) {
        if (std.mem.indexOf(u8, name, "<")) |langle_idx| {
            name = name[0..langle_idx];
        }

        try writer.writeAll(name);
        try writer.writeAll("(");

        var args_i: usize = 0;
        while (args_it.next()) |arg| : (args_i += 1) {
            try clangTypeToZig(arg, fbs);
            if (args_i < args_it.len - 1) try writer.writeAll(", ");
        }

        return writer.writeAll(").Instance");
    } else if (t.isObject()) {
        try writer.writeAll(name);
        try writer.writeAll(".Instance");
        return;
    } else if (t.kind() == .@"enum") {
        const is_options = t.isFlagEnum();
        if (std.mem.startsWith(u8, name, "enum ")) {
            name = name["enum ".len..];
        }

        if (is_options) {
            return writer.print("{s}.Value", .{name});
        } else {
            return writer.writeAll(name);
        }
    } else if (t.kind() == .record) {
        if (std.mem.startsWith(u8, name, "struct ")) {
            name = name["struct ".len..];
        }

        if (std.mem.startsWith(u8, name, "_")) {
            name = name[1..];
        }

        return writer.writeAll(name);
    } else if (t.kind() == .constantArray) {
        try writer.print("[{d}]", .{t.arraySize()});
        return clangTypeToZig(t.arrayElementType(), fbs);
    } else if (t.kind() == .objCTypeParam) {
        if (std.mem.indexOf(u8, name, "<")) |langle_idx| {
            name = name[0..langle_idx];
        }

        return writer.writeAll(name);
    } else if (t.kind() == .objcSel) {
        return writer.writeAll("Sel");
    }

    try writer.writeAll(switch (t.kind()) {
        .void => "void",
        .int => "i32",
        .bool => "bool",
        // FIXME: Support for block pointers
        .blockPointer => "?*anyopaque",
        .char_s, .char_u, .uchar, .schar => "u8",
        .char16 => "u16",
        .char32 => "u32",
        .ushort => "u16",
        .short => "i16",
        .uint => "u32",
        .ulong => "u32",
        .ulonglong => "u64",
        .uint128 => "u128",
        .float => "f32",
        .double => "f64",
        .float128 => "f128",
        .float16 => "f16",
        .long => "i32",
        .longlong => "i64",
        .elaborated => return clangTypeToZig(t.named(), fbs),
        .typedef => return clangTypeToZig(t.typedefUnderlying(), fbs),
        else => |k| {
            std.log.err("Unknown type: {}", .{k});
            return error.UnknownType;
        },
    });
}

pub fn functionPointerToZig(env: *Env, cursor: clang.Cursor, typ: clang.Type) anyerror![]const u8 {
    _ = typ;
    _ = cursor;
    _ = env;
    return "fn_pointer";
}

// pub fn functionPointerToZig(env: *Env, cursor: clang.Cursor, typ: clang.Type) anyerror![]const u8 {
//     const allocator = env.allocator;

//     const return_type = typ.result();
//     var return_zig_type: []const u8 = "";
//     if (return_type.asFunctionPointer()) |proto| {
//         return_zig_type = try functionPointerToZig(env, cursor, proto);
//     } else {
//         var fbs = std.io.fixedBufferStream(&fmt_buf);
//         try clangTypeToZig(return_type, &fbs);
//         return_zig_type = try allocator.dupe(u8, fbs.getWritten());
//     }

//     var visitor = FunctionPointerVisitor{
//         .arguments = std.ArrayList(FunctionPointerVisitor.Arg).init(allocator),
//         .env = env,
//     };

//     clang.visitChildrenUserData(cursor, &visitor, visitFunctionPointer);

//     var proto_buf: [1024]u8 = undefined;
//     var fbs = std.io.fixedBufferStream(&proto_buf);
//     const writer = fbs.writer();

//     try writer.writeAll("*const fn (");
//     if (visitor.arguments.items.len > 0) {
//         for (visitor.arguments.items, 0..) |arg, i| {
//             if (arg.name.len > 0) {
//                 try writer.print("{s}: ", .{arg.name});
//             }
//             try writer.writeAll(arg.typ);
//             if (i < visitor.arguments.items.len - 1) try writer.writeAll(", ");
//         }
//     } else {
//         var i: usize = 0;
//         var args_it = typ.functionArgs();
//         while (args_it.next()) |arg| : (i += 1) {
//             var arg_typ: []const u8 = "";
//             if (arg.asFunctionPointer()) |proto| {
//                 arg_typ = try functionPointerToZig(env, cursor, proto);
//             } else {
//                 var buf: [1024]u8 = undefined;
//                 var typ_fbs = std.io.fixedBufferStream(&buf);
//                 try clangTypeToZig(arg, &typ_fbs);
//                 arg_typ = env.allocator.dupe(u8, typ_fbs.getWritten()) catch @panic("allocate");
//             }

//             try writer.writeAll(arg_typ);
//             if (i < args_it.len - 1) try writer.writeAll(", ");
//         }
//     }
//     try writer.print(") callconv(.C) {s}", .{return_zig_type});

//     return try allocator.dupe(u8, fbs.getWritten());
// }

const FunctionPointerVisitor = struct {
    const Arg = struct { name: []const u8, typ: []const u8 };
    arguments: std.ArrayList(Arg),
    env: *Env,
};

fn visitFunctionPointer(data: *FunctionPointerVisitor, cursor: clang.Cursor, parent: clang.Cursor) clang.VisitorResult {
    _ = parent;
    switch (cursor.kind()) {
        .parmDecl => {
            const name = cursor.spelling();
            defer name.free();

            const owned_name = data.env.allocator.dupe(u8, name.str()) catch @panic("allocate");

            const typ = cursor.typ();
            var zig_typ: []const u8 = "";
            if (typ.asFunctionPointer()) |proto| {
                zig_typ = functionPointerToZig(data.env, cursor, proto) catch @panic("fn pointer conversion");
            } else {
                var typ_fbs = std.io.fixedBufferStream(&fmt_buf);
                clangTypeToZig(typ, &typ_fbs) catch @panic("c to zig type conversion");
                zig_typ = data.env.allocator.dupe(u8, typ_fbs.getWritten()) catch @panic("allocate");
            }

            data.arguments.append(.{ .name = owned_name, .typ = zig_typ }) catch @panic("allocate");

            std.log.debug("found fn pointer arg: {s} type: {s}", .{ owned_name, zig_typ });
        },
        else => {},
    }

    return .continue_;
}
