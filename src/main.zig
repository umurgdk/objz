const std = @import("std");
const clang = @import("clang.zig");
const objz = @import("objz.zig");
const writer = @import("writer.zig");

var fmt_buf: [2048]u8 = undefined;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

var stdout = std.io.getStdOut();

const InterfaceVisitor = struct {
    class: *objz.Class,
    env: *objz.Env,
    protocols: std.ArrayList([]const u8),
    type_args: std.ArrayList([]const u8),
};
const ProtocolVisitor = struct { protocol: *objz.Protocol, env: *objz.Env };
fn EnumVisitor(comptime Value: type, comptime is_signed: bool) type {
    return struct {
        const Self = @This();
        const Case = objz.Enum(Value).Case;

        cases: std.ArrayList(Case),
        is_options: bool,
        env: *objz.Env,
        name: []const u8,

        pub fn visit(data: *Self, cursor: clang.Cursor, parent: clang.Cursor) clang.VisitorResult {
            _ = parent;
            switch (cursor.kind()) {
                clang.CursorKind.flagEnum => data.is_options = true,
                clang.CursorKind.enumConstantDecl => {
                    const case_val: Value = if (is_signed) cursor.enumConstantSignedValue() else cursor.enumConstantValue();
                    const case_name_raw = cursor.displayName();
                    defer case_name_raw.free();

                    var case_str = case_name_raw.str();
                    if (std.mem.startsWith(u8, case_name_raw.str(), data.name)) {
                        case_str = case_str[data.name.len..];
                    }

                    var case_name = data.env.allocator.dupe(u8, case_str) catch @panic("allocate");
                    case_name[0] = std.ascii.toLower(case_name[0]);

                    data.cases.append(Case{ .name = case_name, .value = case_val }) catch @panic("allocate");
                },
                else => {},
            }

            return .continue_;
        }
    };
}
const StructVisitor = struct {
    struct_: *objz.Struct,
    fields: std.ArrayList(objz.Struct.Field),
    env: *objz.Env,
};

pub fn visitProtocol(data: *ProtocolVisitor, cursor: clang.Cursor, parent: clang.Cursor) clang.VisitorResult {
    _ = parent;
    if (!cursor.isValid()) return .break_;

    switch (cursor.kind()) {
        .objCProtocolRef => {
            const name = cursor.spelling();
            defer name.free();

            const proto_name = data.env.allocator.dupe(u8, name.str()) catch @panic("allocate");
            data.protocol.protocols.append(proto_name) catch @panic("allocate");
        },
        .objcClassMethodDecl, .objcInstanceMethodDecl => {
            var method = brk: {
                if (cursor.kind() == .objcClassMethodDecl) {
                    break :brk data.protocol.class_methods.addOne() catch @panic("allocate");
                } else {
                    break :brk data.protocol.instance_methods.addOne() catch @panic("allocate");
                }
            };

            createMethod(cursor, method, data.env) catch unreachable;
        },
        else => {},
    }

    return .continue_;
}

pub fn visitInterface(data: *InterfaceVisitor, cursor: clang.Cursor, parent: clang.Cursor) clang.VisitorResult {
    _ = parent;
    if (!cursor.isValid()) return .break_;

    switch (cursor.kind()) {
        .templateTypeParameter => {
            const name = cursor.spelling();
            defer name.free();

            const owned_name = data.env.allocator.dupe(u8, name.str()) catch @panic("allocate");
            data.type_args.append(owned_name) catch @panic("allocate");
        },
        .objcClassMethodDecl, .objcInstanceMethodDecl => {
            var method = brk: {
                if (cursor.kind() == .objcClassMethodDecl) {
                    break :brk data.class.class_methods.addOne() catch @panic("allocate");
                } else {
                    break :brk data.class.instance_methods.addOne() catch @panic("allocate");
                }
            };

            createMethod(cursor, method, data.env) catch unreachable;
        },
        else => {},
    }

    return .continue_;
}

pub fn visitStruct(data: *StructVisitor, cursor: clang.Cursor, parent: clang.Cursor) clang.VisitorResult {
    _ = parent;
    if (!cursor.isValid()) return .break_;

    switch (cursor.kind()) {
        .fieldDecl => {
            const name_raw = cursor.spelling();
            defer name_raw.free();

            const name = data.env.allocator.dupe(u8, name_raw.str()) catch @panic("allocate");

            const typ = cursor.typ();
            var zig_typ: []const u8 = "";

            if (typ.asFunctionPointer()) |proto| {
                zig_typ = objz.functionPointerToZig(data.env, cursor, proto) catch @panic("fn pointer conversion");
            } else {
                var fbs = std.io.fixedBufferStream(&fmt_buf);
                objz.clangTypeToZig(typ, &fbs) catch |err| switch (err) {
                    error.UnknownType => exitUnkonwnType(cursor, typ),
                    else => @panic(@errorName(err)),
                };

                zig_typ = data.env.allocator.dupe(u8, fbs.getWritten()) catch @panic("allocate");
            }

            data.fields.append(objz.Struct.Field{ .name = name, .typ = zig_typ }) catch @panic("allocate");
        },
        else => |k| {
            const spl = cursor.spelling();
            defer spl.free();

            std.log.debug("Unknown struct cursor: {} {s}", .{ k, spl.str() });
        },
    }
    return .continue_;
}

fn createMethod(cursor: clang.Cursor, method: *objz.Method, env: *objz.Env) anyerror!void {
    var typ_buf: [1024]u8 = undefined;

    const allocator = env.allocator;

    const raw_selector = cursor.spelling();
    defer raw_selector.free();

    var selector = try allocator.dupe(u8, raw_selector.str());

    var arguments = std.ArrayList(objz.Argument).init(allocator);
    var args_it = cursor.args();
    while (args_it.next()) |arg| {
        const raw_name = arg.spelling();
        defer raw_name.free();

        var name = try allocator.dupe(u8, raw_name.str());

        const typ = arg.typ();
        var zig_typ: []const u8 = "";
        if (typ.asFunctionPointer()) |proto| {
            zig_typ = try objz.functionPointerToZig(env, arg, proto);
        } else {
            var typ_fbs = std.io.fixedBufferStream(&typ_buf);
            objz.clangTypeToZig(typ, &typ_fbs) catch |err| switch (err) {
                error.UnknownType => exitUnkonwnType(arg, typ),
                else => @panic(@errorName(err)),
            };
            zig_typ = try allocator.dupe(u8, typ_fbs.getWritten());
        }

        try arguments.append(.{ .name = name, .typ = zig_typ });
    }

    const ret_typ_clang = cursor.returnType();
    var ret_typ_zig: []const u8 = "";
    if (ret_typ_clang.asFunctionPointer()) |proto| {
        ret_typ_zig = try objz.functionPointerToZig(env, cursor, proto);
    } else {
        var ret_typ_fbs = std.io.fixedBufferStream(&typ_buf);
        objz.clangTypeToZig(ret_typ_clang, &ret_typ_fbs) catch |err| switch (err) {
            error.UnknownType => exitUnkonwnType(cursor, ret_typ_clang),
            else => @panic(@errorName(err)),
        };
        ret_typ_zig = try allocator.dupe(u8, ret_typ_fbs.getWritten());
    }

    method.selector = selector;
    method.return_typ = ret_typ_zig;
    method.arguments = arguments.items;
    method.placement = if (cursor.kind() == .objcClassMethodDecl) .class else .instance;
}

fn exitUnkonwnType(cursor: clang.Cursor, typ: clang.Type) noreturn {
    var t = typ;
    if (t.kind() == .elaborated) {
        t = t.canonical();
        std.log.err("Type is elaborated, canonical: {}", .{t.kind()});
    }

    if (t.kind() == .typedef) {
        t = t.canonical();
        std.log.err("Type is a typedef to {}", .{t.kind()});
    }

    if (t.isPointer()) {
        t = t.pointee();
        std.log.err("Type is a pointer pointing to: {}", .{t.kind()});
    }

    const file_loc = cursor.location().fileLocation(&fmt_buf);
    std.log.err("Unsupported type {} at {s}:{d}", .{ typ.kind(), file_loc.path, file_loc.line });
    std.debug.dumpCurrentStackTrace(null);
    std.os.exit(1);
}

pub fn indexDeclaration(env: *objz.Env, info: clang.IndexDeclInfo) void {
    const entity_info = info.raw.*.entityInfo.*;
    const decl_cursor = clang.Cursor{ .raw = info.raw.*.cursor };

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const file_location = decl_cursor.location().fileLocation(&path_buf);

    if (!std.mem.startsWith(u8, file_location.path, env.file_filter)) {
        return;
    }

    var stream = std.io.BufferedWriter(std.mem.page_size, @TypeOf(env.out_file.writer())){
        .unbuffered_writer = env.out_file.writer(),
    };

    switch (entity_info.kind) {
        clang.c.CXIdxEntity_Typedef => {
            const raw_name = entity_info.name;
            const raw_name_len = std.mem.len(raw_name);

            const name = env.allocator.dupe(u8, raw_name[0..raw_name_len]) catch @panic("allocate");

            const underlying_type = decl_cursor.underlyingType().named();

            if (underlying_type.kind() == .record) {
                var struct_ = objz.Struct{ .name = name, .fields = &.{} };
                var visitor = StructVisitor{
                    .struct_ = &struct_,
                    .fields = std.ArrayList(objz.Struct.Field).init(env.allocator),
                    .env = env,
                };

                clang.visitChildrenUserData(underlying_type.declaration(), &visitor, visitStruct);

                struct_.fields = visitor.fields.items;

                writer.writeStruct(&struct_, stream.writer()) catch @panic("write error");
            }
        },
        clang.c.CXIdxEntity_Enum => {
            const raw_name = entity_info.name;
            var name: []const u8 = "";
            if (raw_name != null) {
                const raw_name_len = std.mem.len(raw_name);
                name = env.allocator.dupe(u8, raw_name[0..raw_name_len]) catch @panic("allocate");
            }

            const case_typ = decl_cursor.enumIntegerType();

            if (case_typ.isSigned()) {
                const Visitor = EnumVisitor(i64, true);
                var visitor = Visitor{
                    .env = env,
                    .name = name,
                    .cases = std.ArrayList(Visitor.Case).init(env.allocator),
                    .is_options = false,
                };

                clang.visitChildrenUserData(decl_cursor, &visitor, Visitor.visit);

                var typ_fbs = std.io.fixedBufferStream(&fmt_buf);
                objz.clangTypeToZig(case_typ, &typ_fbs) catch |err| switch (err) {
                    error.UnknownType => exitUnkonwnType(decl_cursor, case_typ),
                    else => @panic(@errorName(err)),
                };

                const Enum = objz.Enum(i64);
                const enum_ = Enum{
                    .cases = visitor.cases.items,
                    .name = name,
                    .typ = typ_fbs.getWritten(),
                    .is_options = visitor.is_options,
                };

                writer.writeEnum(i64, &enum_, stream.writer()) catch @panic("Write error");
            } else {
                const Visitor = EnumVisitor(u64, false);
                var visitor = Visitor{
                    .env = env,
                    .name = name,
                    .cases = std.ArrayList(Visitor.Case).init(env.allocator),
                    .is_options = false,
                };

                clang.visitChildrenUserData(decl_cursor, &visitor, Visitor.visit);

                var typ_fbs = std.io.fixedBufferStream(&fmt_buf);
                objz.clangTypeToZig(case_typ, &typ_fbs) catch |err| switch (err) {
                    error.UnknownType => exitUnkonwnType(decl_cursor, case_typ),
                    else => @panic(@errorName(err)),
                };

                const Enum = objz.Enum(u64);
                const enum_ = Enum{
                    .cases = visitor.cases.items,
                    .name = name,
                    .typ = typ_fbs.getWritten(),
                    .is_options = visitor.is_options,
                };

                writer.writeEnum(u64, &enum_, stream.writer()) catch @panic("write error");
            }
        },
        clang.c.CXIdxEntity_ObjCProtocol => {
            const raw_name: [*:0]const u8 = entity_info.name;
            const name_len = std.mem.len(raw_name);
            var name = env.allocator.dupe(u8, raw_name[0..name_len]) catch @panic("allocate");

            var protocol = objz.Protocol.init(name, env.allocator);
            var data = ProtocolVisitor{ .protocol = &protocol, .env = env };
            const cursor = clang.Cursor{ .raw = info.raw.*.cursor };

            clang.visitChildrenUserData(cursor, &data, visitProtocol);
            writer.writeProtocol(&protocol, stream.writer()) catch @panic("print error");
        },
        clang.c.CXIdxEntity_ObjCClass => {
            const raw_name: [*:0]const u8 = entity_info.name;
            const name_len = std.mem.len(raw_name);
            var name = env.allocator.dupe(u8, raw_name[0..name_len]) catch @panic("allocate");

            const interface_info = clang.c.clang_index_getObjCInterfaceDeclInfo(info.raw).*;
            const super_cursor = clang.Cursor{ .raw = interface_info.superInfo.*.cursor };

            const baseclass_string = super_cursor.spelling();
            defer baseclass_string.free();

            var baseclass = env.allocator.dupe(u8, baseclass_string.str()) catch @panic("allocate");

            const raw_protocols = interface_info.protocols.*;

            const num_protocols = raw_protocols.numProtocols;
            var protocols = env.allocator.alloc([]const u8, interface_info.protocols.*.numProtocols) catch @panic("allocate");

            for (0..num_protocols) |i| {
                const raw_protocol = raw_protocols.protocols[i].*;
                const cursor = clang.Cursor{ .raw = raw_protocol.cursor };
                const spelling = cursor.spelling();
                defer spelling.free();

                const str = spelling.str();

                var protocol = env.allocator.dupe(u8, str) catch @panic("allocate");
                protocols[i] = protocol;
            }

            var class = objz.Class.init(
                name,
                baseclass,
                protocols,
                &.{},
                env.allocator,
            );
            var data = InterfaceVisitor{
                .class = &class,
                .env = env,
                .protocols = std.ArrayList([]const u8).init(env.allocator),
                .type_args = std.ArrayList([]const u8).init(env.allocator),
            };

            const cursor = clang.Cursor{ .raw = info.raw.*.cursor };

            clang.visitChildrenUserData(cursor, &data, visitInterface);

            class.type_args = data.type_args.items;
            writer.writeClass(&class, stream.writer()) catch @panic("print error");
        },
        else => {},
    }

    stream.flush() catch @panic("Write error");
}

pub fn printUsageAndExit() noreturn {
    std.log.err("Usage: objz [file.ast] [outputpath] [filefilter]", .{});
    std.os.exit(1);
}

pub fn abort_cb(env: *objz.Env, reserved: ?*anyopaque) c_int {
    _ = reserved;
    _ = env;
    return 0;
}

pub fn diagnostic(env: *objz.Env, diag_set: clang.DiagnosticSet) void {
    _ = env;

    var diag_it = diag_set.iterator();
    while (diag_it.next()) |diag| {
        const msg = clang.String{ .raw = clang.c.clang_getDiagnosticSpelling(diag.raw) };
        defer msg.free();

        std.log.debug("DIAG: {s}", .{msg.str()});
    }
}

pub fn main() !void {
    var args_it = try std.process.argsWithAllocator(gpa.allocator());
    _ = args_it.skip();

    const test_ast: [:0]const u8 = args_it.next() orelse printUsageAndExit();

    const out_path = args_it.next() orelse printUsageAndExit();

    const file_filter = args_it.next() orelse printUsageAndExit();

    clang.c.clang_uninstall_llvm_fatal_error_handler();
    clang.c.clang_toggleCrashRecovery(0);

    var index = clang.Index.init(true, true) catch {
        std.log.err("Failed to create an index", .{});
        std.os.exit(1);
        return;
    };

    var translation_unit = clang.createTranslationUnit(index, test_ast) catch |err| {
        switch (err) {
            error.TUCreationFailed => std.log.err("create tu failed", .{}),
            error.TUCreationCrashed => std.log.err("create tu crashed", .{}),
            error.TUCreationInvalidAST => std.log.err("create tu failed: ast read err", .{}),
            else => unreachable,
        }

        std.os.exit(1);
    };

    var env = objz.Env{
        .out_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
            std.log.err("Failed to open output file: {!}", .{err});
            std.os.exit(1);
        },
        .file_filter = file_filter,
        .process_dir_path = "",
        .remove_prefix = "",
        .allocator = gpa.allocator(),
    };

    const diagnostics = clang.c.clang_getDiagnosticSetFromTU(translation_unit.raw);
    for (0..clang.c.clang_getNumDiagnosticsInSet(diagnostics)) |i| {
        const diag = clang.c.clang_getDiagnosticInSet(diagnostics, @intCast(i));
        const msg = clang.String{ .raw = clang.c.clang_getDiagnosticSpelling(diag) };
        defer msg.free();

        std.log.debug("DIAG: {s}", .{msg.str()});
    }

    defer env.out_file.close();

    try writer.writeFileHeader(&env);

    clang.indexTranslationUnitUserInfo(
        index,
        translation_unit,
        &env,
        .{
            .indexDeclaration = indexDeclaration,
            .abortQuery = abort_cb,
            .diagnostic = diagnostic,
        },
    ) catch |err| {
        std.log.err("{!}", .{err});
        std.os.exit(1);
    };

    // clang.visitChildrenUserData(translation_unit.cursor(), &env, visitor);

    translation_unit.dispose();
    index.dispose();
}
