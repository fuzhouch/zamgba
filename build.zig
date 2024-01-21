const std = @import("std");

// ====================================================================
// The target definition and gba.ld are from @wendigojaeger's project.
// https://github.com/wendigojaeger/ZigGBA
//

fn buildGBAThumbTarget(b: *std.Build) std.Build.ResolvedTarget {
    var query = std.zig.CrossTarget {
        .cpu_arch = std.Target.Cpu.Arch.thumb,
        .cpu_model = . { .explicit = &std.Target.arm.cpu.arm7tdmi },
        .os_tag = .freestanding,
    };
    query.cpu_features_add.addFeature(@intFromEnum(std.Target.arm.Feature.thumb_mode));
    return std.Build.resolveTargetQuery(b, query);
}

fn libRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const GBALinkerScript = libRoot() ++ "/src/gba.ld";
const GBALibFile = libRoot() ++ "/src/gba.zig";

// ====================================================================

fn addExe(b: *std.Build,
           target: std.Build.ResolvedTarget,
           optimize: std.builtin.OptimizeMode,
           executable: []const u8,
           sourceRoot: []const u8,
           linkToLib: *std.Build.Step.Compile) void {
    const exe = b.addExecutable(.{
        .name = executable,
        .root_source_file = .{ .path = sourceRoot },
        .target = target,
        .optimize = optimize,
    });
    exe.setLinkerScriptPath(std.Build.LazyPath { .path = GBALinkerScript });
    exe.root_module.addAnonymousImport( "gba", .{
            .root_source_file = .{
                .path = GBALibFile
            }
        });
    exe.linkLibrary(linkToLib);

    const objcopy_step = exe.addObjCopy(.{ .format = .bin });
    const install_bin_step = b.addInstallBinFile(
        objcopy_step.getOutputSource(),
        b.fmt("{s}.gba", .{executable}));
    install_bin_step.step.dependOn(&objcopy_step.step);
    b.default_step.dependOn(&install_bin_step.step);
}

fn addStaticLib(b: *std.Build,
                target: std.Build.ResolvedTarget,
                optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "zamgba",
        .root_source_file = .{ .path = GBALibFile },
        .target = target,
        .optimize = optimize,
    });
    lib.setLinkerScriptPath(std.Build.LazyPath { .path = GBALinkerScript });
    return lib;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const gba_thumb_target = buildGBAThumbTarget(b);

    // Core library
    const lib = addStaticLib(b, gba_thumb_target, optimize);
    b.installArtifact(lib);
    b.default_step.dependOn(&lib.step);

    // Demos
    addExe(b, gba_thumb_target, optimize, "first", "demo/first.zig", lib);

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
