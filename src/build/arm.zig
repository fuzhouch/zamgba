// This file includes code to be referenced by build scripts.
// It defines build target for ARM7.
const std = @import("std");

fn libRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const GBALibFile = libRoot() ++ "/../gba.zig";
const GBALinkerScript = libRoot() ++ "/../gba.ld";

fn buildGBAThumbTarget(b: *std.Build) std.Build.ResolvedTarget {
    var query = std.zig.CrossTarget{
        .cpu_arch = std.Target.Cpu.Arch.thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.arm7tdmi },
        .os_tag = .freestanding,
    };
    query.cpu_features_add.addFeature(@intFromEnum(std.Target.arm.Feature.thumb_mode));
    return std.Build.resolveTargetQuery(b, query);
}

pub const GBARomOptions = struct {
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    root_source_file: []const u8,
};

pub fn addROM(b: *std.Build, options: GBARomOptions) *std.Build.Step.Compile {
    const gba_thumb_target = buildGBAThumbTarget(b);
    const rom = b.addExecutable(.{
        .name = options.name,
        .root_source_file = .{ .src_path = .{
            .owner = b,
            .sub_path = options.root_source_file,
        }},
        .target = gba_thumb_target,
        .optimize = options.optimize,
    });
    rom.setLinkerScriptPath(std.Build.LazyPath{ .src_path = .{ 
        .owner = b,
        .sub_path = GBALinkerScript,
    }});

    // Create true rom image that can be recognized by mgba emulator.
    // Known issue: The built executable (in ELF format) can't be
    // executed by mgba emulator, unlike devkitARM. Root cause needs
    // more investigation.
    const objcopy_step = rom.addObjCopy(.{ .format = .bin });
    const install_bin_step = b.addInstallBinFile(
        objcopy_step.getOutputSource(),
        b.fmt("{s}.gba", .{options.name}),
    );

    install_bin_step.step.dependOn(&objcopy_step.step);
    b.default_step.dependOn(&install_bin_step.step);
    return rom;
}

pub fn addStaticLibrary(b: *std.Build, options: GBARomOptions) *std.Build.Step.Compile {
    const gba_thumb_target = buildGBAThumbTarget(b);
    const lib = b.addStaticLibrary(.{
        .name = options.name,
        .root_source_file = .{ .src_path = .{
            .owner = b,
            .sub_path = options.root_source_file,
        }},
        .target = gba_thumb_target,
        .optimize = options.optimize,
    });
    lib.setLinkerScriptPath(std.Build.LazyPath{ .path = GBALinkerScript });
    return lib;
}
