const std = @import("std");
// const system_sdk = @import("vendor/mach-glfw/system_sdk.zig");

/// Use this with addPackage in your project.
pub const pkg = std.build.Pkg{
    .name = "objc",
    .source = .{ .path = thisDir() ++ "/src/main.zig" },
};

/// Returns the module for libxev. The recommended approach is to depend
/// on libxev in your build.zig.zon file, then use
/// `b.dependency("libxev").module("xev")`. But if you're not using
/// a build.zig.zon yet this will work.
pub fn module(b: *std.Build) *std.Build.Module {
    return b.createModule(.{
        .source_file = .{ .path = (comptime thisDir()) ++ "/src/main.zig" },
    });
}

pub fn build(b: *std.Build) !void {
    _ = b;
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
