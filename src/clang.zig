const std = @import("std");
pub const c = @cImport(
    @cInclude("clang-c/Index.h"),
);

var fmt_buf: [2048]u8 = undefined;

pub const String = struct {
    raw: c.CXString,
    pub fn str(self: String) []const u8 {
        const c_str = c.clang_getCString(self.raw);
        const len = std.mem.len(c_str);
        return c_str[0..len];
    }

    pub fn free(self: String) void {
        c.clang_disposeString(self.raw);
    }
};

pub const Index = struct {
    raw: c.CXIndex,

    pub fn init(exclude_declarations_from_pch: bool, display_diagnostics: bool) !Index {
        const index = Index{
            .raw = c.clang_createIndex(
                if (exclude_declarations_from_pch) 1 else 0,
                if (display_diagnostics) 1 else 0,
            ),
        };

        if (index.raw == null) return error.IndexCreationFailed;
        return index;
    }

    pub fn dispose(index: *Index) void {
        c.clang_disposeIndex(index.raw);
        index.raw = null;
    }
};

pub const TranslationUnit = struct {
    raw: c.CXTranslationUnit,

    pub fn cursor(tu: TranslationUnit) Cursor {
        return .{ .raw = c.clang_getTranslationUnitCursor(tu.raw) };
    }

    pub fn dispose(tu: *TranslationUnit) void {
        c.clang_disposeTranslationUnit(tu.raw);
        tu.raw = null;
    }
};

pub fn createTranslationUnit(index: Index, ast_path: [*c]const u8) !TranslationUnit {
    var raw: c.CXTranslationUnit = undefined;

    const err = c.clang_createTranslationUnit2(index.raw, ast_path, &raw);
    return switch (err) {
        c.CXError_Success => if (raw == null) error.TUCreationFailed else TranslationUnit{ .raw = raw },
        c.CXError_Failure => error.TUCreationFailed,
        c.CXError_Crashed => error.TUCreationCrashed,
        c.CXError_InvalidArguments => @panic("Invalid arguments given to clang_createTranslationUnit2"),
        c.CXError_ASTReadError => error.TUCreationInvalidAST,
        else => unreachable,
    };
}

pub fn ClangIter(comptime Elem: type, comptime Container: type, comptime Len: type) type {
    return struct {
        len: Len,
        container: Container,
        accessor: *const fn (container: @TypeOf(@field(@as(Container, undefined), "raw")), i: c_uint) callconv(.C) @TypeOf(@field(@as(Elem, undefined), "raw")),
        i: c_uint = 0,

        pub fn next(self: *@This()) ?Elem {
            if (self.i >= self.len) return null;
            const elem_raw = self.accessor(self.container.raw, self.i);
            const elem = Elem{ .raw = elem_raw };
            self.i += 1;
            return elem;
        }
    };
}

pub const Type = struct {
    raw: c.CXType,

    pub const PointerKind = enum { primitive, object };

    pub fn spelling(t: Type) String {
        var typ = t;
        if (t.isPointer()) return t.pointee().spelling();

        const raw_str = c.clang_getTypeSpelling(typ.raw);
        return .{ .raw = raw_str };
    }

    pub inline fn isConst(t: Type) bool {
        return c.clang_isConstQualifiedType(t.raw) == 1;
    }

    pub inline fn isPointer(t: Type) bool {
        return switch (t.kind()) {
            .pointer => true,
            .objcObjectPointer => true,
            else => false,
        };
    }

    pub inline fn isSigned(t: Type) bool {
        return switch (t.kind()) {
            TypeKind.int,
            TypeKind.int128,
            TypeKind.char_s,
            TypeKind.char16,
            TypeKind.char32,
            TypeKind.float,
            TypeKind.float16,
            TypeKind.float128,
            TypeKind.double,
            TypeKind.long,
            TypeKind.longlong,
            TypeKind.longdouble,
            => true,
            else => false,
        };
    }

    pub inline fn named(t: Type) Type {
        return .{ .raw = c.clang_Type_getNamedType(t.raw) };
    }

    pub inline fn typedefUnderlying(t: Type) Type {
        const decl_raw = c.clang_getTypeDeclaration(t.raw);
        return .{ .raw = c.clang_getTypedefDeclUnderlyingType(decl_raw) };
    }

    pub inline fn nullability(t: Type) ?Nullability {
        var typ: Type = t;

        return switch (c.clang_Type_getNullability(typ.modified().raw)) {
            c.CXTypeNullability_Invalid => null,
            c.CXTypeNullability_NonNull => .nonnull,
            c.CXTypeNullability_Nullable => .nullable,
            c.CXTypeNullability_NullableResult => .nullableResult,
            c.CXTypeNullability_Unspecified => .unspecified,
            else => unreachable,
        };
    }

    pub inline fn isNullable(t: Type) bool {
        const nl = t.nullability() orelse return false;
        return switch (nl) {
            .nullable, .nullableResult => true,
            else => false,
        };
    }

    pub inline fn isInstancetype(t: Type) bool {
        const spell = t.spelling();
        defer spell.free();

        return std.mem.eql(u8, spell.str(), "instancetype");
    }

    pub inline fn isId(t: Type) bool {
        if (t.kind() == .objcId) return true;
        if (t.pointerKind() == .object) {
            const obj_typ = t.pointee();
            return obj_typ.protocols().len > 0;
        }

        return false;
    }

    pub inline fn isObject(t: Type) bool {
        return switch (t.kind()) {
            TypeKind.objcClass,
            TypeKind.objcInterface,
            TypeKind.objCObject,
            => true,
            else => false,
        };
    }

    pub inline fn kind(t: Type) TypeKind {
        return @as(TypeKind, @enumFromInt(t.raw.kind));
    }

    pub inline fn declaration(t: Type) Cursor {
        return .{ .raw = c.clang_getTypeDeclaration(t.raw) };
    }

    pub fn isFlagEnum(t: Type) bool {
        const decl = t.declaration();
        var result = false;
        visitChildrenUserData(decl, &result, flagEnumVisitor);
        return result;
    }

    fn flagEnumVisitor(is_flag_enum: *bool, cursor: Cursor, parent: Cursor) VisitorResult {
        _ = parent;
        switch (cursor.kind()) {
            CursorKind.flagEnum => is_flag_enum.* = true,
            else => {},
        }

        return .continue_;
    }

    pub inline fn kindSpelling(t: Type) String {
        return .{ .raw = c.clang_getTypeKindSpelling(t.raw.kind) };
    }

    pub inline fn pointerKind(t: Type) ?PointerKind {
        return switch (t.kind()) {
            .pointer => .primitive,
            .objcObjectPointer => .object,
            else => null,
        };
    }

    pub inline fn pointee(t: Type) Type {
        return .{ .raw = c.clang_getPointeeType(t.raw) };
    }

    pub inline fn args(t: Type) ClangIter(Type, Type, c_uint) {
        var typ = t;
        if (t.pointerKind() == .object) {
            typ = t.pointee();
        }

        const len = c.clang_Type_getNumObjCTypeArgs(typ.raw);
        return .{
            .len = len,
            .container = typ,
            .accessor = c.clang_Type_getObjCTypeArg,
        };
    }

    pub inline fn canonical(t: Type) Type {
        return .{ .raw = c.clang_getCanonicalType(t.raw) };
    }

    pub inline fn modified(t: Type) Type {
        return .{ .raw = c.clang_Type_getModifiedType(t.raw) };
    }

    pub inline fn valueType(t: Type) Type {
        return .{ .raw = c.clang_Type_getValueType(t.raw) };
    }

    pub inline fn isValid(t: Type) bool {
        return t.raw.kind != c.CXType_Invalid;
    }

    pub inline fn eql(t: Type, other: Type) bool {
        return c.clang_equalTypes(t.raw, other.raw) == 1;
    }

    pub inline fn protocols(t: Type) ClangIter(Cursor, Type, c_uint) {
        var typ = t;
        if (typ.pointerKind() == .object) {
            typ = typ.pointee();
        }

        const len = c.clang_Type_getNumObjCProtocolRefs(typ.raw);
        return .{
            .len = len,
            .container = typ,
            .accessor = c.clang_Type_getObjCProtocolDecl,
        };
    }

    pub inline fn classType(t: Type) Type {
        return .{ .raw = c.clang_Type_getClassType(t.raw) };
    }

    pub fn print(t: Type, prefix: []const u8) anyerror!void {
        var typ = t;
        const name = typ.spelling();
        defer name.free();

        const kind_spell = typ.kindSpelling();
        defer kind_spell.free();

        var i: usize = 0;
        var proto_it = t.protocols();
        var args_it = t.args();

        std.log.debug("        {s} [num_protocols={d}] [num_type_args={d}] [kind={s}] [name={s}] [is_id={}] [is_const={}] [is_nullable={}]", .{
            prefix,
            proto_it.len,
            args_it.len,
            kind_spell.str(),
            name.str(),
            typ.isId(),
            typ.isConst(),
            typ.pointee().isNullable(),
        });

        if (t.pointerKind() == .primitive) {
            return t.pointee().print("    (points_to)");
        }

        {
            const can = t.canonical();
            if (!t.eql(can)) {
                try can.print("    (canonical)");
            }
        }

        {
            const cls = t.classType();
            if (!t.eql(cls) and cls.isValid()) {
                try cls.print("    (class)");
            }
        }

        {
            const mod = t.modified();
            if (!t.eql(mod) and mod.isValid()) {
                try mod.print("    (modified)");
            }
        }

        {
            const val = t.valueType();
            if (!t.eql(val) and val.isValid()) {
                try val.print("    (value)");
            }
        }

        if (t.isId()) {
            while (proto_it.next()) |proto| : (i += 1) {
                const proto_name = proto.spelling();
                defer proto_name.free();

                std.log.debug("            (proto {d}): {s}", .{ i, proto_name.str() });
            }
        } else {
            while (args_it.next()) |arg| : (i += 1) {
                var fbs = std.io.fixedBufferStream(&fmt_buf);
                const writer = fbs.writer();

                try writer.print("    (generic {d})", .{i});
                try arg.print(fbs.getWritten());
            }
        }
    }
};

pub const Location = struct {
    raw: c.CXSourceLocation,

    pub inline fn isFromMainFile(l: Location) bool {
        return c.clang_Location_isFromMainFile(l.raw) == 1;
    }

    pub inline fn fileLocation(l: Location, path_buf: []u8) FileLocation {
        var file: c.CXFile = undefined;
        var file_loc: FileLocation = undefined;

        c.clang_getFileLocation(
            l.raw,
            &file,
            &file_loc.line,
            &file_loc.column,
            &file_loc.offset,
        );

        const path = String{ .raw = c.clang_getFileName(file) };
        defer path.free();

        const path_str = path.str();

        @memcpy(path_buf[0..path_str.len], path_str);
        file_loc.path = path_buf[0..path_str.len];
        return file_loc;
    }
};

pub const FileLocation = struct {
    path: []const u8,
    line: c_uint,
    column: c_uint,
    offset: c_uint,
};

pub const Cursor = struct {
    raw: c.CXCursor,

    pub inline fn kind(cur: Cursor) CursorKind {
        const kind_raw = c.clang_getCursorKind(cur.raw);
        return @as(CursorKind, @enumFromInt(kind_raw));
    }

    pub inline fn spelling(cur: Cursor) String {
        const raw_str = c.clang_getCursorSpelling(cur.raw);
        return .{ .raw = raw_str };
    }

    pub inline fn location(cur: Cursor) Location {
        return .{ .raw = c.clang_getCursorLocation(cur.raw) };
    }

    pub inline fn args(cur: Cursor) ClangIter(Cursor, Cursor, c_int) {
        const len = c.clang_Cursor_getNumArguments(cur.raw);
        return .{
            .len = len,
            .container = cur,
            .accessor = c.clang_Cursor_getArgument,
        };
    }

    pub inline fn enumIntegerType(cur: Cursor) Type {
        return .{ .raw = c.clang_getEnumDeclIntegerType(cur.raw) };
    }

    pub inline fn enumConstantValue(cur: Cursor) u64 {
        return @intCast(c.clang_getEnumConstantDeclUnsignedValue(cur.raw));
    }

    pub inline fn enumConstantSignedValue(cur: Cursor) i64 {
        return @intCast(c.clang_getEnumConstantDeclValue(cur.raw));
    }

    pub inline fn typ(cur: Cursor) Type {
        return .{ .raw = c.clang_getCursorType(cur.raw) };
    }

    pub inline fn returnType(cur: Cursor) Type {
        return .{ .raw = c.clang_getCursorResultType(cur.raw) };
    }

    pub inline fn methodSign(cur: Cursor) u8 {
        return switch (cur.kind()) {
            c.CXCursor_ObjCClassMethodDecl => '+',
            c.CXCursor_ObjCInstanceMethodDecl => '-',
            else => @panic("Cursor is not a method declaration"),
        };
    }

    pub inline fn isOptional(cur: Cursor) bool {
        return c.clang_Cursor_isObjCOptional(cur.raw) == 1;
    }

    pub inline fn isValid(cur: Cursor) bool {
        return c.clang_isInvalid(@intFromEnum(cur.kind())) == 0;
    }

    pub inline fn displayName(cur: Cursor) String {
        return .{ .raw = c.clang_getCursorDisplayName(cur.raw) };
    }

    pub inline fn underlyingType(cur: Cursor) Type {
        return .{ .raw = c.clang_getTypedefDeclUnderlyingType(cur.raw) };
    }

    pub fn printMethod(cur: Cursor) anyerror!void {
        const name = cur.displayName();
        defer name.free();

        var args_it = cur.args();

        std.log.debug("    {s} [num_args={d}]", .{ name.str(), args_it.len });
        try cur.returnType().print("(return)");

        var i: usize = 0;
        while (args_it.next()) |arg| : (i += 1) {
            var fbs = std.io.fixedBufferStream(&fmt_buf);
            const writer = fbs.writer();

            const arg_name = arg.spelling();
            defer arg_name.free();

            try writer.print("(arg {d}: {s})", .{ i, arg_name.str() });
            try arg.typ().print(fbs.getWritten());
        }
    }
};

pub const VisitorResult = enum(c_uint) {
    break_ = 0,
    continue_ = 1,
    recurse = 2,
};

pub fn visitChildren(cursor: Cursor, func: *const fn (Cursor, Cursor) VisitorResult) void {
    _ = c.clang_visitChildren(cursor.raw, rawVisitChildren, @ptrCast(@constCast(func)));
}

fn rawVisitChildren(c_cursor: c.CXCursor, c_parent: c.CXCursor, client_data: c.CXClientData) callconv(.C) c.CXChildVisitResult {
    var func = @as(?*fn (Cursor, Cursor) VisitorResult, @ptrCast(@alignCast(client_data))) orelse @panic("clang client data is null");
    const result = func(.{ .raw = c_cursor }, .{ .raw = c_parent });
    const result_raw = @intFromEnum(result);
    return result_raw;
}

pub fn visitChildrenUserData(cursor: Cursor, client_data: anytype, func: *const fn (@TypeOf(client_data), Cursor, Cursor) VisitorResult) void {
    const Closure = VisitorClosure(@TypeOf(client_data));
    const closure = Closure{
        .data = client_data,
        .func = func,
    };

    _ = c.clang_visitChildren(cursor.raw, Closure.visitor, @ptrCast(@constCast(&closure)));
}

fn VisitorClosure(comptime Data: type) type {
    return struct {
        data: Data,
        func: *const fn (Data, Cursor, Cursor) VisitorResult,
        pub fn visitor(raw_cursor: c.CXCursor, raw_parent: c.CXCursor, data: c.CXClientData) callconv(.C) c.CXChildVisitResult {
            var closure = @as(?*@This(), @ptrCast(@alignCast(data))) orelse @panic("clang client data is null");
            const result = closure.func(closure.data, .{ .raw = raw_cursor }, .{ .raw = raw_parent });
            return @intFromEnum(result);
        }
    };
}

pub const CursorKind = enum(c_uint) {
    const firstDecl = CursorKind.unexposedDecl;
    const lastDecl = CursorKind.cxxAccessSpecifier;
    const firstRef = CursorKind.objCSuperClassRef;
    const lastRef = CursorKind.variableRef;
    const firstInvalid = CursorKind.invalidFile;
    const lastInvalid = CursorKind.invalidCode;
    const firstExpr = CursorKind.unexposedExpr;
    const lastExpr = CursorKind.cxxParenListInitExpr;
    const asmStmt = CursorKind.gccAsmStmt;
    const firstStmt = CursorKind.unexposedStmt;
    const lastStmt = CursorKind.ompErrorDirective;
    const firstAttr = CursorKind.unexposedAttr;
    const lastAttr = CursorKind.alignedAttr;
    const macroInstantiation = CursorKind.macroExpansion;
    const firstProcessing = CursorKind.preprocessingDirective;
    const lastProcessing = CursorKind.inclusionDirective;
    const firstExtraDecl = CursorKind.moduleImportDecl;
    const lastExtraDecl = CursorKind.conceptDecl;

    unexposedDecl = 1,
    structDecl = 2,
    unionDecl = 3,
    classDecl = 4,
    enumDecl = 5,
    fieldDecl = 6,
    enumConstantDecl = 7,
    functionDecl = 8,
    varDecl = 9,
    parmDecl = 10,
    objcInterfaceDecl = 11,
    objcCategoryDecl = 12,
    objcProtocolDecl = 13,
    objcPropertyDecl = 14,
    objcIvarDecl = 15,
    objcInstanceMethodDecl = 16,
    objcClassMethodDecl = 17,
    objcImplementationDecl = 18,
    objcCategoryImplDecl = 19,
    typedefDecl = 20,
    cxxMethod = 21,
    namespace = 22,
    linkageSpec = 23,
    constructor = 24,
    destructor = 25,
    conversionFunction = 26,
    templateTypeParameter = 27,
    nonTypeTemplateParameter = 28,
    templateTemplateParameter = 29,
    functionTemplate = 30,
    classTemplate = 31,
    classTemplatePartialSpecialization = 32,
    namespaceAlias = 33,
    usingDirective = 34,
    usingDeclaration = 35,
    typeAliasDecl = 36,
    objCSynthesizeDecl = 37,
    objCDynamicDecl = 38,
    cxxAccessSpecifier = 39,
    objCSuperClassRef = 40,
    objCProtocolRef = 41,
    objCClassRef = 42,
    typeRef = 43,
    cxxBaseSpecifier = 44,
    templateRef = 45,
    namespaceRef = 46,
    memberRef = 47,
    labelRef = 48,
    overloadedDeclRef = 49,
    variableRef = 50,
    invalidFile = 70,
    noDeclFound = 71,
    notImplemented = 72,
    invalidCode = 73,
    unexposedExpr = 100,
    declRefExpr = 101,
    memberRefExpr = 102,
    callExpr = 103,
    objCMessageExpr = 104,
    blockExpr = 105,
    integerLiteral = 106,
    floatingLiteral = 107,
    imaginaryLiteral = 108,
    stringLiteral = 109,
    characterLiteral = 110,
    parenExpr = 111,
    unaryOperator = 112,
    arraySubscriptExpr = 113,
    binaryOperator = 114,
    compoundAssignOperator = 115,
    conditionalOperator = 116,
    cStyleCastExpr = 117,
    compoundLiteralExpr = 118,
    initListExpr = 119,
    addrLabelExpr = 120,
    stmtExpr = 121,
    genericSelectionExpr = 122,
    gNUNullExpr = 123,
    cxxStaticCastExpr = 124,
    cxxDynamicCastExpr = 125,
    cxxReinterpretCastExpr = 126,
    cxxConstCastExpr = 127,
    cxxFunctionalCastExpr = 128,
    cxxTypeidExpr = 129,
    cxxBoolLiteralExpr = 130,
    cxxNullPtrLiteralExpr = 131,
    cxxThisExpr = 132,
    cxxThrowExpr = 133,
    cxxNewExpr = 134,
    cxxDeleteExpr = 135,
    unaryExpr = 136,
    objCStringLiteral = 137,
    objCEncodeExpr = 138,
    objCSelectorExpr = 139,
    objCProtocolExpr = 140,
    objCBridgedCastExpr = 141,
    packExpansionExpr = 142,
    sizeOfPackExpr = 143,
    lambdaExpr = 144,
    objCBoolLiteralExpr = 145,
    objCSelfExpr = 146,
    ompArraySectionExpr = 147,
    objCAvailabilityCheckExpr = 148,
    fixedPointLiteral = 149,
    ompArrayShapingExpr = 150,
    ompIteratorExpr = 151,
    cxxAddrspaceCastExpr = 152,
    conceptSpecializationExpr = 153,
    requiresExpr = 154,
    cxxParenListInitExpr = 155,
    unexposedStmt = 200,
    labelStmt = 201,
    compoundStmt = 202,
    caseStmt = 203,
    defaultStmt = 204,
    ifStmt = 205,
    switchStmt = 206,
    whileStmt = 207,
    doStmt = 208,
    forStmt = 209,
    gotoStmt = 210,
    indirectGotoStmt = 211,
    continueStmt = 212,
    breakStmt = 213,
    returnStmt = 214,
    gccAsmStmt = 215,
    objCAtTryStmt = 216,
    objCAtCatchStmt = 217,
    objCAtFinallyStmt = 218,
    objCAtThrowStmt = 219,
    objCAtSynchronizedStmt = 220,
    objCAutoreleasePoolStmt = 221,
    objCForCollectionStmt = 222,
    cxxCatchStmt = 223,
    cxxTryStmt = 224,
    cxxForRangeStmt = 225,
    sEHTryStmt = 226,
    sEHExceptStmt = 227,
    sEHFinallyStmt = 228,
    mSAsmStmt = 229,
    nullStmt = 230,
    declStmt = 231,
    ompParallelDirective = 232,
    ompSimdDirective = 233,
    ompForDirective = 234,
    ompSectionsDirective = 235,
    ompSectionDirective = 236,
    ompSingleDirective = 237,
    ompParallelForDirective = 238,
    ompParallelSectionsDirective = 239,
    ompTaskDirective = 240,
    ompMasterDirective = 241,
    ompCriticalDirective = 242,
    ompTaskyieldDirective = 243,
    ompBarrierDirective = 244,
    ompTaskwaitDirective = 245,
    ompFlushDirective = 246,
    sEHLeaveStmt = 247,
    ompOrderedDirective = 248,
    ompAtomicDirective = 249,
    ompForSimdDirective = 250,
    ompParallelForSimdDirective = 251,
    ompTargetDirective = 252,
    ompTeamsDirective = 253,
    ompTaskgroupDirective = 254,
    ompCancellationPointDirective = 255,
    ompCancelDirective = 256,
    ompTargetDataDirective = 257,
    ompTaskLoopDirective = 258,
    ompTaskLoopSimdDirective = 259,
    ompDistributeDirective = 260,
    ompTargetEnterDataDirective = 261,
    ompTargetExitDataDirective = 262,
    ompTargetParallelDirective = 263,
    ompTargetParallelForDirective = 264,
    ompTargetUpdateDirective = 265,
    ompDistributeParallelForDirective = 266,
    ompDistributeParallelForSimdDirective = 267,
    ompDistributeSimdDirective = 268,
    ompTargetParallelForSimdDirective = 269,
    ompTargetSimdDirective = 270,
    ompTeamsDistributeDirective = 271,
    ompTeamsDistributeSimdDirective = 272,
    ompTeamsDistributeParallelForSimdDirective = 273,
    ompTeamsDistributeParallelForDirective = 274,
    ompTargetTeamsDirective = 275,
    ompTargetTeamsDistributeDirective = 276,
    ompTargetTeamsDistributeParallelForDirective = 277,
    ompTargetTeamsDistributeParallelForSimdDirective = 278,
    ompTargetTeamsDistributeSimdDirective = 279,
    builtinBitCastExpr = 280,
    ompMasterTaskLoopDirective = 281,
    ompParallelMasterTaskLoopDirective = 282,
    ompMasterTaskLoopSimdDirective = 283,
    ompParallelMasterTaskLoopSimdDirective = 284,
    ompParallelMasterDirective = 285,
    ompDepobjDirective = 286,
    ompScanDirective = 287,
    ompTileDirective = 288,
    ompCanonicalLoop = 289,
    ompInteropDirective = 290,
    ompDispatchDirective = 291,
    ompMaskedDirective = 292,
    ompUnrollDirective = 293,
    ompMetaDirective = 294,
    ompGenericLoopDirective = 295,
    ompTeamsGenericLoopDirective = 296,
    ompTargetTeamsGenericLoopDirective = 297,
    ompParallelGenericLoopDirective = 298,
    ompTargetParallelGenericLoopDirective = 299,
    ompParallelMaskedDirective = 300,
    ompMaskedTaskLoopDirective = 301,
    ompMaskedTaskLoopSimdDirective = 302,
    ompParallelMaskedTaskLoopDirective = 303,
    ompParallelMaskedTaskLoopSimdDirective = 304,
    ompErrorDirective = 305,
    translationUnit = 350,
    unexposedAttr = 400,
    ibActionAttr = 401,
    ibOutletAttr = 402,
    ibOutletCollectionAttr = 403,
    cxxFinalAttr = 404,
    cxxOverrideAttr = 405,
    annotateAttr = 406,
    asmLabelAttr = 407,
    packedAttr = 408,
    pureAttr = 409,
    constAttr = 410,
    noDuplicateAttr = 411,
    cudaConstantAttr = 412,
    cudaDeviceAttr = 413,
    cudaGlobalAttr = 414,
    cudaHostAttr = 415,
    cudaSharedAttr = 416,
    visibilityAttr = 417,
    dllExport = 418,
    dllImport = 419,
    nsReturnsRetained = 420,
    nsReturnsNotRetained = 421,
    nsReturnsAutoreleased = 422,
    nsConsumesSelf = 423,
    nsConsumed = 424,
    objCException = 425,
    objCNSObject = 426,
    objCIndependentClass = 427,
    objCPreciseLifetime = 428,
    objCReturnsInnerPointer = 429,
    objCRequiresSuper = 430,
    objCRootClass = 431,
    objCSubclassingRestricted = 432,
    objCExplicitProtocolImpl = 433,
    objCDesignatedInitializer = 434,
    objCRuntimeVisible = 435,
    objCBoxable = 436,
    flagEnum = 437,
    convergentAttr = 438,
    warnUnusedAttr = 439,
    warnUnusedResultAttr = 440,
    alignedAttr = 441,
    preprocessingDirective = 500,
    macroDefinition = 501,
    macroExpansion = 502,
    inclusionDirective = 503,
    moduleImportDecl = 600,
    typeAliasTemplateDecl = 601,
    staticAssert = 602,
    friendDecl = 603,
    conceptDecl = 604,
    overloadCandidate = 700,

    pub fn spelling(k: CursorKind) String {
        return .{ .raw = c.clang_getCursorKindSpelling(@intFromEnum(k)) };
    }

    pub fn raw(k: CursorKind) c_uint {
        return @intFromEnum(k);
    }
};

pub const TypeKind = enum(c_int) {
    const firstBuiltin = TypeKind.void;
    const lastBuiltin = TypeKind.ibm128;

    invalid = 0,
    unexposed = 1,
    void = 2,
    bool = 3,
    char_u = 4,
    uchar = 5,
    char16 = 6,
    char32 = 7,
    ushort = 8,
    uint = 9,
    ulong = 10,
    ulonglong = 11,
    uint128 = 12,
    char_s = 13,
    schar = 14,
    wchar = 15,
    short = 16,
    int = 17,
    long = 18,
    longlong = 19,
    int128 = 20,
    float = 21,
    double = 22,
    longdouble = 23,
    nullPtr = 24,
    overload = 25,
    dependent = 26,
    objcId = 27,
    objcClass = 28,
    objcSel = 29,
    float128 = 30,
    half = 31,
    float16 = 32,
    shortAccum = 33,
    accum = 34,
    longAccum = 35,
    ushortAccum = 36,
    uaccum = 37,
    ulongAccum = 38,
    bfloat16 = 39,
    ibm128 = 40,
    complex = 100,
    pointer = 101,
    blockPointer = 102,
    lvalueReference = 103,
    rvalueReference = 104,
    record = 105,
    @"enum" = 106,
    typedef = 107,
    objcInterface = 108,
    objcObjectPointer = 109,
    functionNoProto = 110,
    functionProto = 111,
    constantArray = 112,
    vector = 113,
    incompleteArray = 114,
    variableArray = 115,
    dependentSizedArray = 116,
    memberPointer = 117,
    auto = 118,
    elaborated = 119,
    pipe = 120,
    oclImage1dRO = 121,
    oclImage1dArrayRO = 122,
    oclImage1dBufferRO = 123,
    oclImage2dRO = 124,
    oclImage2dArrayRO = 125,
    oclImage2dDepthRO = 126,
    oclImage2dArrayDepthRO = 127,
    oclImage2dMSAARO = 128,
    oclImage2dArrayMSAARO = 129,
    oclImage2dMSAADepthRO = 130,
    oclImage2dArrayMSAADepthRO = 131,
    oclImage3dRO = 132,
    oclImage1dWO = 133,
    oclImage1dArrayWO = 134,
    oclImage1dBufferWO = 135,
    oclImage2dWO = 136,
    oclImage2dArrayWO = 137,
    oclImage2dDepthWO = 138,
    oclImage2dArrayDepthWO = 139,
    oclImage2dMSAAWO = 140,
    oclImage2dArrayMSAAWO = 141,
    oclImage2dMSAADepthWO = 142,
    oclImage2dArrayMSAADepthWO = 143,
    oclImage3dWO = 144,
    oclImage1dRW = 145,
    oclImage1dArrayRW = 146,
    oclImage1dBufferRW = 147,
    oclImage2dRW = 148,
    oclImage2dArrayRW = 149,
    oclImage2dDepthRW = 150,
    oclImage2dArrayDepthRW = 151,
    oclImage2dMSAARW = 152,
    oclImage2dArrayMSAARW = 153,
    oclImage2dMSAADepthRW = 154,
    oclImage2dArrayMSAADepthRW = 155,
    oclImage3dRW = 156,
    oclSampler = 157,
    oclEvent = 158,
    oclQueue = 159,
    oclReserveID = 160,
    objCObject = 161,
    objCTypeParam = 162,
    attributed = 163,
    oclIntelSubgroupAVCMcePayload = 164,
    oclIntelSubgroupAVCImePayload = 165,
    oclIntelSubgroupAVCRefPayload = 166,
    oclIntelSubgroupAVCSicPayload = 167,
    oclIntelSubgroupAVCMceResult = 168,
    oclIntelSubgroupAVCImeResult = 169,
    oclIntelSubgroupAVCRefResult = 170,
    oclIntelSubgroupAVCSicResult = 171,
    oclIntelSubgroupAVCImeResultSingleRefStreamout = 172,
    oclIntelSubgroupAVCImeResultDualRefStreamout = 173,
    oclIntelSubgroupAVCImeSingleRefStreamin = 174,
    oclIntelSubgroupAVCImeDualRefStreamin = 175,
    extVector = 176,
    atomic = 177,
    btfTagAttributed = 178,
};

pub const Nullability = enum(c_int) {
    nonnull = 0,
    nullable = 1,
    unspecified = 2,
    invalid = 3,
    nullableResult = 4,
};

pub const Diagnostic = struct {
    raw: c.CXDiagnostic,
};

pub const DiagnosticSet = struct {
    raw: c.CXDiagnosticSet,

    pub fn iterator(ds: DiagnosticSet) Iterator {
        const len = c.clang_getNumDiagnosticsInSet(ds.raw);
        _ = len;
    }

    pub const Iterator = struct {
        len: c_uint,
        raw: c.CXDiagnosticSet,
        cursor: c_uint = 0,

        pub fn next(it: *Iterator) ?Diagnostic {
            if (it.cursor >= it.len) return null;
            const diagnostic = .{ .raw = c.clang_getDiagnosticInSet(it.raw, it.cursor) };
            it.cursor += 1;
            return diagnostic;
        }
    };
};

pub const File = struct {
    raw: c.CXFile,
};

pub const IndexClientFile = struct {
    raw: c.CXIdxClientFile,
};

pub const IndexClientASTFile = struct {
    raw: c.CXIdxClientASTFile,
};

pub const IndexIncludedFileInfo = struct {
    raw: *const c.CXIdxIncludedFileInfo,
};

pub const IndexImportedASTFileInfo = struct {
    raw: *const c.CXIdxImportedASTFileInfo,
};

pub const IndexClientContainer = struct {
    raw: c.CXIdxClientContainer,
};

pub const IndexDeclInfo = struct {
    raw: *const c.CXIdxDeclInfo,
};

pub const IndexEntityRefInfo = struct {
    raw: *const c.CXIdxEntityRefInfo,
};

// _ = c.clang_indexTranslationUnit(index_action, c.NULL, callbacks_ptr, @sizeOf(c.IndexerCallbacks), c.CXIndexOpt_None, translation_unit);
pub fn indexTranslationUnitUserInfo(
    index: Index,
    translation_unit: TranslationUnit,
    user_info: anytype,
    callbacks: IndexClosure(@TypeOf(user_info)).Callbacks,
) void {
    const Closure = IndexClosure(@TypeOf(user_info));
    var closure = Closure{ .data = user_info, .callbacks = callbacks };

    var action = c.clang_IndexAction_create(index.raw);
    var raw_callbacks = c.IndexerCallbacks{
        .abortQuery = if (callbacks.abortQuery != null) Closure.abortQuery else null,
        .diagnostic = if (callbacks.diagnostic != null) Closure.diagnostic else null,
        .enteredMainFile = if (callbacks.enteredMainFile != null) Closure.enteredMainFile else null,
        .ppIncludedFile = if (callbacks.ppIncludedFile != null) Closure.ppIncludedFile else null,
        .importedASTFile = if (callbacks.importedASTFile != null) Closure.importedASTFile else null,
        .startedTranslationUnit = if (callbacks.startedTranslationUnit != null) Closure.startedTranslationUnit else null,
        .indexDeclaration = if (callbacks.indexDeclaration != null) Closure.indexDeclaration else null,
        .indexEntityReference = if (callbacks.indexEntityReference != null) Closure.indexEntityReference else null,
    };

    _ = c.clang_indexTranslationUnit(action, &closure, &raw_callbacks, Closure.callbacks_size, c.CXIndexOpt_None, translation_unit.raw);
}

fn IndexClosure(comptime Data: type) type {
    return struct {
        data: Data,
        callbacks: Callbacks,

        const callbacks_size = @sizeOf(Callbacks);
        const Callbacks = struct {
            abortQuery: ?*const fn (Data, ?*anyopaque) c_int = null,
            diagnostic: ?*const fn (Data, DiagnosticSet) void = null,
            enteredMainFile: ?*const fn (Data, File, ?*anyopaque) IndexClientFile = null,
            ppIncludedFile: ?*const fn (Data, IndexIncludedFileInfo) IndexClientFile = null,
            importedASTFile: ?*const fn (Data, IndexImportedASTFileInfo) IndexClientASTFile = null,
            startedTranslationUnit: ?*const fn (Data, ?*anyopaque) IndexClientContainer = null,
            indexDeclaration: ?*const fn (Data, IndexDeclInfo) void = null,
            indexEntityReference: ?*const fn (Data, IndexEntityRefInfo) void = null,
        };

        fn closureFrom(client_data: c.CXClientData) *@This() {
            return @as(?*@This(), @ptrCast(@alignCast(client_data))) orelse @panic("clang client data is null");
        }

        pub fn abortQuery(client_data: c.CXClientData, reserved: ?*anyopaque) callconv(.C) c_int {
            var closure = closureFrom(client_data);
            return closure.callbacks.abortQuery.?(closure.data, reserved);
        }

        pub fn diagnostic(client_data: c.CXClientData, raw_set: c.CXDiagnosticSet, reserved: ?*anyopaque) callconv(.C) void {
            _ = reserved;
            var closure = closureFrom(client_data);
            const set = DiagnosticSet{ .raw = raw_set };
            closure.callbacks.diagnostic.?(closure.data, set);
        }

        pub fn enteredMainFile(client_data: c.CXClientData, raw_file: c.CXFile, reserved: ?*anyopaque) callconv(.C) c.CXIdxClientFile {
            var closure = closureFrom(client_data);
            const file = File{ .raw = raw_file };
            const result = closure.callbacks.enteredMainFile.?(closure.data, file, reserved);
            return result.raw;
        }

        pub fn ppIncludedFile(client_data: c.CXClientData, info_raw: [*c]const c.CXIdxIncludedFileInfo) callconv(.C) c.CXIdxClientFile {
            var closure = closureFrom(client_data);
            const info = IndexIncludedFileInfo{ .raw = @ptrCast(info_raw) };
            const result = closure.callbacks.ppIncludedFile.?(closure.data, info);
            return result.raw;
        }

        pub fn importedASTFile(client_data: c.CXClientData, info_raw: [*c]const c.CXIdxImportedASTFileInfo) callconv(.C) c.CXIdxClientASTFile {
            var closure = closureFrom(client_data);
            const info = IndexImportedASTFileInfo{ .raw = @ptrCast(info_raw) };
            const result = closure.callbacks.importedASTFile.?(closure.data, info);
            return result.raw;
        }

        pub fn startedTranslationUnit(client_data: c.CXClientData, reserved: ?*anyopaque) callconv(.C) c.CXIdxClientContainer {
            var closure = closureFrom(client_data);
            const result = closure.callbacks.startedTranslationUnit.?(closure.data, reserved);
            return result.raw;
        }

        pub fn indexDeclaration(client_data: c.CXClientData, info_raw: [*c]const c.CXIdxDeclInfo) callconv(.C) void {
            var closure = closureFrom(client_data);
            const info = IndexDeclInfo{ .raw = @ptrCast(info_raw) };
            closure.callbacks.indexDeclaration.?(closure.data, info);
        }

        pub fn indexEntityReference(client_data: c.CXClientData, info_raw: [*c]const c.CXIdxEntityRefInfo) callconv(.C) void {
            var closure = closureFrom(client_data);
            const info = IndexEntityRefInfo{ .raw = @ptrCast(info_raw) };
            closure.callbacks.indexEntityReference.?(closure.data, info);
        }
    };
}
