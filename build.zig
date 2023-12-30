const std = @import("std");

// ====================================================================
// The target definition and gba.ld are from @wendigojaeger's project.
// https://github.com/wendigojaeger/ZigGBA
//
const gba_thumb_target = blk: {
    var target = std.zig.CrossTarget {
        .cpu_arch = std.Target.Cpu.Arch.thumb,
        .cpu_model = . { .explicit = &std.Target.arm.cpu.arm7tdmi },
        .os_tag = .freestanding,
    };

    target.cpu_features_add.addFeature(@intFromEnum(std.Target.arm.Feature.thumb_mode));
    break :blk target;
};

fn libRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const GBALinkerScript = libRoot() ++ "/src/gba.ld";

// ====================================================================

fn addDemo(b: *std.Build,
           target: std.zig.CrossTarget,
           optimize: std.builtin.OptimizeMode,
           executable: []const u8,
           sourceRoot: []const u8) void {
    const demo = b.addExecutable(.{
        .name = executable,
        .root_source_file = .{ .path = sourceRoot },
        .target = target,
        .optimize = optimize,
    });
    demo.setLinkerScriptPath(std.build.FileSource { .path = GBALinkerScript });
    b.installArtifact(demo);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zamgba",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = gba_thumb_target,
        .optimize = optimize,
    });
    lib.setLinkerScriptPath(std.build.FileSource { .path = GBALinkerScript });
    b.installArtifact(lib);

    // All demos - Note that all executables must be run via emulator.
    addDemo(b, gba_thumb_target, optimize, "first.elf", "demo/first.zig");
    addDemo(b, gba_thumb_target, optimize, "first.c.elf", "demo/first.c");

    // TODO Though not sure whether doable, let's keep unit test anyway.
    // Some logic should be able to run on devbox.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
