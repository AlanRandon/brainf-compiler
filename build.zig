const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const runtime_lib_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });

    const runtime_obj = b.addObject(.{
        .name = "brainf-runtime",
        .root_module = runtime_lib_mod,
    });
    runtime_obj.bundle_compiler_rt = true;

    const obj_install = b.addInstallBinFile(runtime_obj.getEmittedBin(), "brainf.o");
    b.default_step.dependOn(&obj_install.step);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const clap = b.dependency("clap", .{});
    exe_mod.addImport("clap", clap.module("clap"));

    const exe = b.addExecutable(.{
        .name = "bfc",
        .root_module = exe_mod,
    });

    exe.linkLibC();
    exe.linkSystemLibrary("LLVM-19");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const lib_unit_tests = b.addTest(.{ .root_module = runtime_lib_mod });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_lib_unit_tests.step);
}
