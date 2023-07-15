const std = @import("std");
const objz = @import("objz.zig");

var fmt_buf: [2048]u8 = undefined;

const ZigKeywords = std.ComptimeStringMap([]const u8, .{
    .{ "const", "const_" },
    .{ "error", "error_" },
    .{ "volatile", "volatile_" },
    .{ "struct", "struct_" },
    .{ "enum", "enum_" },
    .{ "fn", "fn_" },
    .{ "comptime", "comptime_" },
    .{ "type", "type_" },
    .{ "align", "align_" },
    .{ "opaque", "opaque_" },
    .{ "resume", "resume_" },
    .{ "null", "null_" },
});

fn clearZigKeyword(str: []const u8) []const u8 {
    return ZigKeywords.get(str) orelse str;
}

fn clearEnumField(str: []const u8) []const u8 {
    var clear = clearZigKeyword(str);
    if (std.ascii.isDigit(clear[0])) {
        clear = std.fmt.bufPrint(&fmt_buf, "_{s}", .{clear}) catch unreachable;
    }

    return clear;
}

fn IndentedWriter(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,
        level: usize = 0,

        fn indent(self: *Self) anyerror!void {
            var level_i: isize = @intCast(self.level);
            while (level_i > 0) : (level_i -= 1) {
                try self.writer.writeAll("    ");
            }
        }

        pub fn pushLevel(self: *Self) void {
            self.level += 1;
        }

        pub fn popLevel(self: *Self) void {
            self.level -= 1;
        }

        pub fn writeLine(self: *Self, bytes: []const u8) anyerror!void {
            try self.writer.writeAll(bytes);
            try self.writer.writeByte('\n');
        }

        pub fn writeLineIndent(self: *Self, bytes: []const u8) anyerror!void {
            try self.indent();
            try self.writer.writeAll(bytes);
            try self.writer.writeByte('\n');
        }

        pub fn printLine(self: *Self, comptime fmt: []const u8, args: anytype) anyerror!void {
            try self.writer.print(fmt, args);
            try self.writer.writeByte('\n');
        }

        pub fn printLineIndent(self: *Self, comptime fmt: []const u8, args: anytype) anyerror!void {
            try self.indent();
            try self.writer.print(fmt, args);
            try self.writer.writeByte('\n');
        }

        pub fn write(self: *Self, bytes: []const u8) anyerror!void {
            try self.writer.writeAll(bytes);
        }

        pub fn writeIndent(self: *Self, bytes: []const u8) anyerror!void {
            try self.indent();
            try self.writer.writeAll(bytes);
        }

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) anyerror!void {
            try self.writer.print(fmt, args);
        }

        pub fn printIndent(self: *Self, comptime fmt: []const u8, args: anytype) anyerror!void {
            try self.indent();
            try self.writer.print(fmt, args);
        }
    };
}

fn indentedWriter(writer: anytype) IndentedWriter(@TypeOf(writer)) {
    return .{ .writer = writer };
}

pub fn writeProtocol(p: *const objz.Protocol, underlying_writer: anytype) anyerror!void {
    var writer = indentedWriter(underlying_writer);

    try writer.printLine("pub const {s} = struct {{", .{p.name});
    writer.pushLevel();

    try writer.writeLineIndent("pub const conforms_to = .{");
    writer.pushLevel();
    for (p.protocols.items) |proto| {
        try writer.printLineIndent("{s},", .{proto});
    }
    writer.popLevel();
    try writer.writeLineIndent("};");

    try writer.printLineIndent("const __protocol_name = \"{s}\";\n", .{p.name});

    if (p.class_methods.items.len > 0) {
        try writer.writeLineIndent("pub fn ClassMethods(comptime Class__: type, comptime Instance__: type) type {");
        writer.pushLevel();
        try writer.writeLineIndent("return struct {");
        writer.pushLevel();
        try writer.writeLineIndent("const __dis_class = Class__;");
        try writer.writeLineIndent("const __dis_instance = Instance__;");
        for (p.class_methods.items) |*method| {
            try writeMethod(method, "Class__.", &writer);
        }
        writer.popLevel();
        try writer.writeLineIndent("};");
        writer.popLevel();
        try writer.writeLineIndent("}");
    }

    if (p.instance_methods.items.len > 0) {
        try writer.writeLineIndent("pub fn InstanceMethods(comptime Instance__: type) type {");
        writer.pushLevel();
        try writer.writeLineIndent("return struct {");
        writer.pushLevel();
        for (p.instance_methods.items) |*method| {
            try writeMethod(method, "", &writer);
        }
        writer.popLevel();
        try writer.writeLineIndent("};");
        writer.popLevel();
        try writer.writeLineIndent("}");
    }

    writer.popLevel();
    try writer.writeLine("};\n");
}

pub fn writeEnum(comptime CaseValue: type, e: *const objz.Enum(CaseValue), underlying_writer: anytype) anyerror!void {
    var writer = indentedWriter(underlying_writer);

    if (e.name.len == 0) {
        try writer.writeLine("");
        for (e.cases) |case| {
            try writer.printLine("pub const {s} = {d};", .{ clearEnumField(case.name), case.value });
        }
        try writer.writeLine("");
        return;
    }

    if (e.is_options) {
        try writer.printLineIndent("pub const {s} = struct {{", .{e.name});
        writer.pushLevel();

        try writer.printLineIndent("pub const Value = {s};", .{e.typ});

        for (e.cases) |case| {
            try writer.printLineIndent("pub const {s} = {d};", .{ clearEnumField(case.name), case.value });
        }

        writer.popLevel();
        try writer.writeLineIndent("};");
    } else {
        try writer.printLineIndent("pub const {s} = enum({s}) {{", .{ e.name, e.typ });
        writer.pushLevel();
        for (e.cases) |case| {
            try writer.printLineIndent("{s} = {d},", .{ clearEnumField(case.name), case.value });
        }
        writer.popLevel();
        try writer.writeLineIndent("};");
    }

    try writer.writeLine("");
}

pub fn writeStruct(struct_: *const objz.Struct, underlying_writer: anytype) anyerror!void {
    var writer = indentedWriter(underlying_writer);

    try writer.printLine("pub const {s} = extern struct {{", .{struct_.name});

    writer.pushLevel();
    for (struct_.fields) |field| {
        try writer.printLineIndent("{s}: {s},", .{ clearZigKeyword(field.name), field.typ });
    }
    writer.popLevel();

    try writer.writeLine("};\n");
}

pub fn writeClass(c: *const objz.Class, underlying_writer: anytype) anyerror!void {
    var writer = indentedWriter(underlying_writer);

    if (c.isGeneric()) {
        try writer.print("pub fn {s}(", .{c.name});
        for (c.type_args, 0..) |arg, i| {
            try writer.print("comptime {s}: type", .{arg});
            if (i < c.type_args.len - 1) try writer.write(", ");
        }
        try writer.writeLine(") type {");
        writer.pushLevel();
        try writer.writeLineIndent("return struct {");
        writer.pushLevel();
        for (c.type_args, 0..) |arg, i| {
            try writer.printLineIndent("const __arg_discard{d} = {s};", .{ i, arg });
        }
    } else {
        try writer.printLine("pub const {s} = struct {{", .{c.name});
        writer.pushLevel();
    }

    try writer.writeLineIndent("const Self = @This();");

    try writer.printLineIndent("pub const __class_name = \"{s}\";", .{c.name});
    try writer.writeLineIndent("var __class: ?objc.Class = null;\n");

    try writer.writeLineIndent("pub const conforms_to = .{");

    writer.pushLevel();
    for (c.protocols) |protocol| {
        try writer.printLineIndent("{s},", .{protocol});
    }
    writer.popLevel();

    try writer.writeLineIndent("};\n");

    try writeInstace(c, &writer);

    try writer.writeLineIndent("");

    const methods = c.class_methods.items;
    for (methods, 0..) |*method, i| {
        try writeMethod(method, "", &writer);
        if (i < methods.len - 1) try writer.write("\n");
    }

    try writer.writeLineIndent("");

    var lines_it = std.mem.splitScalar(u8, class_methods, '\n');
    while (lines_it.next()) |line| {
        try writer.writeLineIndent(line);
    }

    writer.popLevel();

    if (c.isGeneric()) {
        try writer.writeLineIndent("};");
        writer.popLevel();
        try writer.writeLine("}\n");
    } else {
        try writer.writeLine("};\n");
    }
}

fn writeInstace(c: *const objz.Class, writer: anytype) anyerror!void {
    try writer.writeLineIndent("pub const Instance__ = struct {");
    writer.pushLevel();

    try writer.writeLineIndent("pub const conforms_to = Self.conforms_to;");

    try writer.writeLineIndent("__object: objc.Object,");
    try writer.writeLine("");

    var methods = c.instance_methods.items;
    for (methods, 0..) |*method, i| {
        try writeMethod(method, "", writer);
        if (i < methods.len - 1) try writer.writeLine("");
    }

    var call_line_it = std.mem.splitScalar(u8, instance_methods, '\n');
    while (call_line_it.next()) |line| {
        try writer.writeLineIndent(line);
    }

    writer.popLevel();
    try writer.writeLineIndent("};");
}

fn writeMethod(m: *const objz.Method, class_call: []const u8, writer: anytype) anyerror!void {
    const name = try m.fnName(&fmt_buf);
    if (m.placement == .class) {
        try writer.printIndent("pub inline fn {s}(", .{clearZigKeyword(name)});
    } else {
        try writer.printIndent("pub inline fn {s}(self: Instance__", .{clearZigKeyword(name)});
    }

    for (m.arguments, 0..) |argument, i| {
        if (i == 0 and m.placement == .instance) try writer.write(", ");
        try writer.print("{s}__: {s}", .{ argument.name, argument.typ });
        if (i < m.arguments.len - 1) try writer.write(", ");
    }

    try writer.printLine(") {s} {{", .{m.return_typ});
    writer.pushLevel();

    if (m.placement == .class) {
        try writer.printIndent("return {s}__call({s}, sel(\"{s}\"), .{{", .{ class_call, m.return_typ, m.selector });
    } else {
        try writer.printIndent("return self.__call({s}, sel(\"{s}\"), .{{", .{ m.return_typ, m.selector });
    }
    for (m.arguments, 0..) |argument, i| {
        try writer.print("{s}__", .{argument.name});
        if (i < m.arguments.len - 1) try writer.write(", ");
    }
    try writer.writeLine("});");
    writer.popLevel();

    try writer.writeLineIndent("}");
}

pub fn writeFileHeader(env: *objz.Env) anyerror!void {
    const writer = env.out_file.writer();

    try writer.writeAll("");
    try writer.writeAll("");
    try writer.writeAll(
        \\const objz = @import("objz");
        \\const objc = @import("objc");
        \\const sel = objc.sel;
        \\const Sel = objc.Sel;
        \\
        \\const Id = objz.Id;
        \\const NSObject = objz.NSObject;
        \\const Class = objz.Class;
        \\
        \\
    );
}

const instance_methods: []const u8 =
    \\pub inline fn __call(self: Instance__, comptime ReturnType: type, selector__: objc.Sel, args__: anytype) ReturnType {
    \\    if (comptime objz.isInstanceType(ReturnType)) {
    \\        const instance = self.__object.msgSend(objc.Object, selector__, args__);
    \\        return ReturnType{ .__object = instance };
    \\    } else {
    \\        return self.__object.msgSend(ReturnType, selector__, args__);
    \\    }
    \\}
    \\
;

const class_methods: []const u8 =
    \\inline fn class__() objc.Class {
    \\    if (Self.__class) |cls| return cls;
    \\    Self.__class = objc.Class.getClass(Self.__class_name).?;
    \\    return Self.__class.?;
    \\}
    \\
    \\pub inline fn alloc() Instance__ {
    \\    return __call(Instance__, objc.sel("alloc"), .{});
    \\}
    \\
    \\pub inline fn __call(comptime ReturnType: type, selector__: objc.Sel, args__: anytype) ReturnType {
    \\    if (comptime objz.isInstanceType(ReturnType)) {
    \\        const instance = class__().msgSend(objc.Object, selector__, args__);
    \\        return ReturnType{ .__object = instance };
    \\    } else {
    \\        return class__().msgSend(ReturnType, selector__, args__);
    \\    }
    \\}
    \\
    \\
;
