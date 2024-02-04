// This file includes code to be referenced by build scripts.
// It defines build target for ARM7.
const std = @import("std");

fn libRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const GBALinkerScript = libRoot() ++ "/../gba.ld";
const GBALibFile = libRoot() ++ "/../gba.zig";

pub fn buildGBAThumbTarget(b: *std.Build) std.Build.ResolvedTarget {
    var query = std.zig.CrossTarget{
        .cpu_arch = std.Target.Cpu.Arch.thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.arm7tdmi },
        .os_tag = .freestanding,
    };
    query.cpu_features_add.addFeature(@intFromEnum(std.Target.arm.Feature.thumb_mode));
    return std.Build.resolveTargetQuery(b, query);
}

pub fn addROM(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    executable: []const u8,
    sourceRoot: []const u8,
    linkToLib: *std.Build.Step.Compile,
) void {
    const exe = b.addExecutable(.{
        .name = executable,
        .root_source_file = .{ .path = sourceRoot },
        .target = target,
        .optimize = optimize,
    });
    exe.setLinkerScriptPath(std.Build.LazyPath{ .path = GBALinkerScript });
    exe.root_module.addAnonymousImport("gba", .{
        .root_source_file = .{
            .path = GBALibFile,
        },
    });
    exe.linkLibrary(linkToLib);

    b.installArtifact(exe);

    const objcopy_step = exe.addObjCopy(.{ .format = .bin });
    const install_bin_step = b.addInstallBinFile(
        objcopy_step.getOutputSource(),
        b.fmt(
            "{s}.gba",
            .{executable},
        ),
    );
    install_bin_step.step.dependOn(&objcopy_step.step);
    b.default_step.dependOn(&install_bin_step.step);
}

pub fn addStaticLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "zamgba",
        .root_source_file = .{ .path = GBALibFile },
        .target = target,
        .optimize = optimize,
    });
    lib.setLinkerScriptPath(std.Build.LazyPath{ .path = GBALinkerScript });
    return lib;
}
