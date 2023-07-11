const std = @import("std");
const objz = @import("objz.zig");

var fmt_buf: [2048]u8 = undefined;

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

pub fn writeProtocol(p: *const objz.Protocol, stream: *std.io.StreamSource) anyerror!void {
    var writer = indentedWriter(stream.writer());

    try writer.printLine("pub const {s} = struct {{", .{p.name});
    writer.pushLevel();

    try writer.printLineIndent("const __protocol_name = \"{s}\";\n", .{p.name});

    if (p.class_methods.items.len > 0) {
        try writer.writeLineIndent("pub const ClassMethods = struct {");
        writer.pushLevel();
        for (p.class_methods.items) |*method| {
            try writeMethod(method, &writer);
        }
        writer.popLevel();
        try writer.writeLineIndent("};");
    }

    if (p.instance_methods.items.len > 0) {
        try writer.writeLineIndent("pub fn InstanceMethods(comptime Instance: type) type {");
        writer.pushLevel();
        try writer.writeLineIndent("return struct {");
        writer.pushLevel();
        for (p.instance_methods.items) |*method| {
            try writeMethod(method, &writer);
        }
        writer.popLevel();
        try writer.writeLineIndent("};");
        writer.popLevel();
        try writer.writeLineIndent("}");
    }

    writer.popLevel();
    try writer.writeLine("};\n");
}

pub fn writeClass(c: *const objz.Class, stream: *std.io.StreamSource) anyerror!void {
    var writer = indentedWriter(stream.writer());

    try writer.printLine("pub const {s} = struct {{", .{c.name});
    writer.pushLevel();

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
        try writeMethod(method, &writer);
        if (i < methods.len - 1) try writer.write("\n");
    }

    try writer.writeLineIndent("");

    var lines_it = std.mem.splitScalar(u8, class_methods, '\n');
    while (lines_it.next()) |line| {
        try writer.writeLineIndent(line);
    }

    writer.popLevel();
    try writer.writeLine("};\n");
}

fn writeInstace(c: *const objz.Class, writer: anytype) anyerror!void {
    try writer.writeLineIndent("pub const Instance = struct {");
    writer.pushLevel();

    try writer.writeLineIndent("__object: objc.Object,");
    try writer.writeLine("");

    var methods = c.instance_methods.items;
    for (methods, 0..) |*method, i| {
        try writeMethod(method, writer);
        if (i < methods.len - 1) try writer.writeLine("");
    }

    const call_met =
        \\pub fn __call(self: Self, comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
        \\    if (ReturnType == Self) {
        \\        const instance = self.__object.msgSend(objc.Object, selector, args);
        \\        return Self{ .__object = instance };
        \\    } else {
        \\        return self.__object.msgSend(ReturnType, selector, args);
        \\    }
        \\}
        \\
    ;

    var call_line_it = std.mem.splitScalar(u8, call_met, '\n');
    while (call_line_it.next()) |line| {
        try writer.writeLineIndent(line);
    }

    writer.popLevel();
    try writer.writeLineIndent("};");
}

fn writeMethod(m: *const objz.Method, writer: anytype) anyerror!void {
    const name = try m.fnName(&fmt_buf);
    if (m.placement == .class) {
        try writer.printIndent("pub inline fn {s}(", .{name});
    } else {
        try writer.printIndent("pub inline fn {s}(self: Instance", .{name});
    }

    for (m.arguments, 0..) |argument, i| {
        if (i == 0 and m.placement == .instance) try writer.write(", ");
        try writer.print("{s}__: {s}", .{ argument.name, argument.typ });
        if (i < m.arguments.len - 1) try writer.write(", ");
    }

    try writer.printLine(") {s} {{", .{m.return_typ});
    writer.pushLevel();

    if (m.placement == .class) {
        try writer.printIndent("return __call({s}, sel(\"{s}\"), .{{", .{ m.return_typ, m.selector });
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
        \\
        \\const NSString = objz.NSString;
        \\const NSDictionary = objz.NSDictionary;
        \\
        \\
    );
}

const class_methods: []const u8 =
    \\inline fn class() objc.Class {
    \\    if (Self.__class) |cls| return cls;
    \\    Self.__class = objc.Class.getClass(Self.__class_name).?;
    \\    return Self.__class.?;
    \\}
    \\
    \\pub inline fn alloc() Instance {
    \\    return __call(Instance, objc.sel("alloc"), .{});
    \\}
    \\
    \\pub inline fn __call(comptime ReturnType: type, selector: objc.Sel, args: anytype) ReturnType {
    \\    if (ReturnType == Instance) {
    \\        const instance = class().msgSend(objc.Object, selector, args);
    \\        return Instance{ .object = instance };
    \\    } else {
    \\        return class().msgSend(ReturnType, selector, args);
    \\    }
    \\}
;
