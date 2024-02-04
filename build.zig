const std = @import("std");
const arm = @import("./src/build/arm.zig");

fn libRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const GBALibFile = libRoot() ++ "/src/gba.zig";
const FirstDemoRoot = libRoot() ++ "/demo/first.zig";

// ====================================================================
// The target definition and gba.ld are initialized from two projects:
//
// https://github.com/wendigojaeger/ZigGBA
// https://github.com/ryankurte/rust-gba
//
// It has been modified to fit the changes in zamgba.
//
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const gba_thumb_target = arm.buildGBAThumbTarget(b);

    // Core library
    const lib = arm.addStaticLib(b, gba_thumb_target, optimize, "zamgba", GBALibFile);
    b.installArtifact(lib);
    b.default_step.dependOn(&lib.step);

    // Demos

    arm.addROM(b, gba_thumb_target, optimize, "first", FirstDemoRoot, lib);

    // TODO Though not sure whether doable, let's keep unit test anyway.
    // Some logic should be able to run on devbox.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/ut.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
