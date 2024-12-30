const std = @import("std");

const TargetQuery = std.Target.Query;

// All the targets for which a pre-compiled build of wgpu-native is currently (as of July 9, 2024) available
const target_whitelist = [_]TargetQuery{
    TargetQuery{ .cpu_arch = .aarch64, .os_tag = .linux },
    TargetQuery{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    },
    TargetQuery{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    },
    TargetQuery{
        .cpu_arch = .x86_64,
        .os_tag = .macos,
    },
    TargetQuery{
        .cpu_arch = .x86,
        .os_tag = .windows,
    },
    TargetQuery{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
    },
};

pub fn build(b: *std.Build) void {
    // Get target based on the host system
    const target = b.standardTargetOptions(.{
        .whitelist = &target_whitelist,
    });

    // Leave optimization level at default, but you can change it
    const optimize = b.standardOptimizeOption(.{});

    // Define the executable
    const exe = b.addExecutable(.{
        .name = "sdfs",
        .target = target,
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
    });

    // Add the wgpu-native dependency
    const wgpu_native_dep = b.dependency("wgpu-native-zig", .{});
    exe.root_module.addImport("wgpu", wgpu_native_dep.module("wgpu"));

    // Add the mach-glfw dependency
    const mach_glfw_dep = b.dependency("mach-glfw", .{});
    exe.root_module.addImport("mach-glfw", mach_glfw_dep.module("mach-glfw"));

    // Create an executable artifact
    const target_output = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&target_output.step);

    // Assign a run artifact to the executable
    // We can now call `zig build run` to run the executable
    const run_cmd = b.addRunArtifact(exe);
    const run_cmd_step = b.step("run", "Run the executable");
    run_cmd_step.dependOn(&run_cmd.step);
}
