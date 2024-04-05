const std = @import("std");
const gpu = @import("mach_gpu");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build wchip
    const exe = b.addExecutable(.{
        .name = "wchip",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    try gpu.link(b, exe, &exe.root_module, .{});
    exe.root_module.addImport("glfw", b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    }).module("mach-glfw"));
    exe.root_module.addImport("gpu", b.dependency("mach_gpu", .{
        .target = target,
        .optimize = optimize,
    }).module("mach-gpu"));

    // zig build run implementation
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // zig build test implementation
    const test_lib_chip = b.addTest(.{
        .root_source_file = .{ .path = "src/chip8.zig" },
        .target = target,
        .optimize = optimize,
    });
    const test_step = b.step("test", "Run unit tests");
    const run_test = b.addRunArtifact(test_lib_chip);
    run_test.setCwd(b.dependency("chip8_test_suite", .{}).path("/bin"));
    test_step.dependOn(&run_test.step);
}
