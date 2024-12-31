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

    // Get the wgpu-native dependency
    const wgpu_native_dep = b.dependency("wgpu-native-zig", .{});
    const wgpu = wgpu_native_dep.module("wgpu");

    // Get the mach-glfw dependency
    const mach_glfw_dep = b.dependency("mach-glfw", .{});
    const glfw = mach_glfw_dep.module("mach-glfw");

    // -- Create Hax module --

    const hax = b.addModule("hax", .{
        .root_source_file = b.path("src/hax.zig"),
        .optimize = optimize,
        .target = target,
    });
    hax.addImport("wgpu", wgpu);
    hax.addImport("mach-glfw", glfw);

    // -- Create the triangle example executable --

    const triangle = b.addExecutable(.{
        .name = "triangle-example",
        .target = target,
        .root_source_file = b.path("examples/triangle/main.zig"),
        .optimize = optimize,
    });
    triangle.root_module.addImport("hax", hax);
    triangle.root_module.addImport("wgpu", wgpu);
    triangle.root_module.addImport("mach-glfw", glfw);

    // Assign a run artifact to the executable
    // We can now call `zig build run` to run the executable
    const triangle_cmd = b.addRunArtifact(triangle);
    const triangle_step = b.step("run", "Run the executable");
    triangle_step.dependOn(&triangle_cmd.step);

    b.installArtifact(triangle);
}
