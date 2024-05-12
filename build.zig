const std = @import("std");

// Pub is a must. User projects use it to reference to zamgba's build
// script.
pub const arm = @import("./src/build/arm.zig");

fn libRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const GBALibFile = libRoot() ++ "/src/gba.zig";
const FirstDemoRoot = libRoot() ++ "/demo/first.zig";

const LibName = "zamgba";

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

    // Define a module that can be referenced by client project.
    // It's also the interface for client project to consume zamgba.
    //
    // Note: the module name can change fast as zamgba is in an
    // early stage. To keep a stable @import("...") names in
    // client project, consider defining alias in root_module.addImport().
    //
    // see https://github.com/fuzhouch/consumezamgba for how to use it.
    const m = b.addModule(LibName, .{ .root_source_file = .{
        .src_path = .{
            .owner = b,
            .sub_path = GBALibFile
        },
    }});

    // Step 2: Create demo executables
    var first = arm.addROM(b, .{
        .optimize = optimize,
        .name = "first",
        .root_source_file = FirstDemoRoot,
    });

    first.root_module.addImport(LibName, m);

    // Though not sure whether doable, let's keep unit test anyway.
    // Some logic should be able to run on devbox.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{
            .src_path = . {
                .owner = b,
                .sub_path = "src/ut.zig"
            },
        },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
