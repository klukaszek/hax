// hax.zig: A spiritual successor to Nano.c
// Author: Kyle Lukaszek
// Made Possible By: mach-glfw and wgpu-native-zig
// License: MIT & Apache-2.0

const std = @import("std");
const wgpu = @import("wgpu");
const glfw = @import("mach-glfw");
const builtin = @import("builtin");

// --- Structs ---
pub const ContextDescriptor = struct {
    width: u32 = 640,
    height: u32 = 480,
    title: ?[*:0]const u8 = "hax",
};

pub const ProgramDescriptor = struct {
    init: fn () void = undefined,
    update: fn () void = undefined,
    draw: fn () void = undefined,
    cleanup: fn () void = undefined,
};

// -- Swapchain / Surface Namespace --

pub const Swapchain = struct {
    surface: *wgpu.Surface = undefined,
    config: *wgpu.SurfaceConfiguration = undefined,

    // Configure our WebGPU surface for the target platform. Mac OS X is not supported yet, I need to write a C++ wrapper.
    pub fn configure_for_platform(ctx: *Context) void {
        // Check GLFW platform and create the appropriate surface for WebGPU
        switch (glfw.getPlatform()) {
            .x11 => {
                const backend = glfw.Native(.{ .x11 = true });
                ctx.swapchain.surface = ctx.instance.createSurface(&wgpu.SurfaceDescriptor{
                    .next_in_chain = @ptrCast(&wgpu.SurfaceDescriptorFromXlibWindow{
                        .chain = wgpu.ChainedStruct{
                            .s_type = wgpu.SType.surface_descriptor_from_xlib_window,
                        },
                        .window = backend.getX11Window(ctx.window),
                        .display = backend.getX11Display(),
                    }),
                    .label = "Zig WebGPU X11 Surface",
                }).?;
                std.debug.print("X11 surface created\n", .{});
            },
            .wayland => {
                const backend = glfw.Native(.{ .wayland = true });
                ctx.swapchain.surface = ctx.instance.createSurface(&wgpu.SurfaceDescriptor{
                    .next_in_chain = @ptrCast(&wgpu.SurfaceDescriptorFromWaylandSurface{
                        .chain = wgpu.ChainedStruct{
                            .s_type = wgpu.SType.surface_descriptor_from_wayland_surface,
                        },
                        .surface = backend.getWaylandWindow(ctx.window),
                        .display = backend.getWaylandDisplay(),
                    }),
                    .label = "Zig WebGPU Wayland Surface",
                }).?;
                std.debug.print("Wayland surface created\n", .{});
            },
            .cocoa => {
                // const cocoa_window = glfw.Native(.{ .cocoa = true }).getCocoaWindow(window);
                // TODO: Implement a C++ wrapper around the NSView to get the Metal layer
            },
            .win32 => {
                // The compiler will only check for windows.h if the target is windows
                if (builtin.os.tag == .windows) {
                    std.debug.print("Windows detected\n", .{});
                    const windows = @cImport({
                        @cInclude("windows.h");
                    });
                    const hinstance = windows.GetModuleHandleA(null) orelse {
                        std.log.err("Failed to get module handle\n", .{});
                        return glfw.ErrorCode.PlatformUnavailable;
                    };
                    ctx.swapchain.surface = ctx.instance.createSurface(&wgpu.SurfaceDescriptor{
                        .next_in_chain = @ptrCast(&wgpu.SurfaceDescriptorFromHwnd{
                            .chain = wgpu.ChainedStruct{
                                .s_type = wgpu.SType.surface_descriptor_from_hwnd,
                            },
                            .hinstance = hinstance,
                            .hwnd = glfw.Native(.{ .win32 = true }).getWin32Window(ctx.window),
                        }),
                        .label = "Zig WebGPU Win32 Surface",
                    }).?;
                } else {
                    std.log.err("Windows platform not supported\n", .{});
                }
            },
            else => {
                std.log.err("Unsupported platform\n", .{});
            },
        }
    }

    // Reconfigure our surface when needed.
    pub fn reconfigure(ctx: *Context) void {
        const dimensions = ctx.window.getSize();
        ctx.swapchain.config.width = dimensions.width;
        ctx.swapchain.config.height = dimensions.height;
        ctx.swapchain.surface.configure(ctx.swapchain.config);
    }

    pub fn acquire_next_frame(ctx: *Context) wgpu.SurfaceTexture {
        // Acquire the next swapchain texture
        var surface_texture: wgpu.SurfaceTexture = undefined;
        ctx.swapchain.surface.getCurrentTexture(&surface_texture);
        const stat = wgpu.GetCurrentTextureStatus;
        switch (surface_texture.status) {
            stat.success => {},
            stat.timeout, stat.outdated, stat.lost => {
                Swapchain.reconfigure(ctx);
            },
            else => {
                std.debug.print("Surface texture error: {}\n", .{surface_texture.status});
            },
        }
        return surface_texture;
    }
};

// --- Context Namespace ---

pub const HaxError = error{
    NoAdapter,
    NoDevice,
};

pub const Context = struct {
    window: glfw.Window = undefined,
    instance: *wgpu.Instance = undefined,
    adapter: *wgpu.Adapter = undefined,
    device: *wgpu.Device = undefined,
    queue: *wgpu.Queue = undefined,
    desc: *ContextDescriptor = undefined,
    swapchain: Swapchain = {},

    // Initialize the context
    pub fn initialize(desc: *ContextDescriptor) HaxError!Context {
        if (!glfw.init(.{})) {
            std.log.err("Failed to initialize GLFW: {?s}\n", .{glfw.getErrorString()});
            std.process.exit(1);
        }

        var self: Context = undefined;
        self.desc = desc;

        // Create our WebGPU instance
        var instance = wgpu.Instance.create(null).?;
        self.instance = instance;

        // Create a GLFW window with no API context
        const hints: glfw.Window.Hints = .{
            .client_api = .no_api,
        };
        const window: glfw.Window = glfw.Window.create(desc.width, desc.height, desc.title.?, null, null, hints) orelse {
            std.log.err("Failed to initialize GLFW window: {?s}\n", .{glfw.getErrorString()});
            std.process.exit(1);
        };
        self.window = window;

        // Set the self struct as the user pointer of the window
        glfw.Window.setUserPointer(window, &self);
        glfw.Window.setKeyCallback(window, glfw_key_callback);

        Swapchain.configure_for_platform(&self);

        // Request a high-performance adapter now that we have a surface
        const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{
            .power_preference = .high_performance,
            .compatible_surface = self.swapchain.surface,
        });
        const adapter: *wgpu.Adapter = switch (adapter_request.status) {
            .success => adapter_request.adapter.?,
            else => return error.NoAdapter,
        };
        self.adapter = adapter;

        // Request a device from the adapter
        const device_request = adapter.requestDeviceSync(&wgpu.DeviceDescriptor{
            .required_limits = null,
            .label = "Zig WebGPU Device",
        });
        const device: *wgpu.Device = switch (device_request.status) {
            .success => device_request.device.?,
            else => return error.NoDevice,
        };
        self.device = device;

        // Get the queue from the device
        const queue = device.getQueue().?;
        self.queue = queue;

        std.debug.print("Device {*}\n", .{device});
        print_adapter_info(@constCast(self.adapter));

        // Configure the swapchain surface
        const dimensions = window.getSize();
        const swapchain_format = wgpu.TextureFormat.bgra8_unorm_srgb;
        const config = wgpu.SurfaceConfiguration{
            .device = device,
            .width = dimensions.width,
            .height = dimensions.height,
            .format = swapchain_format,
            .present_mode = .fifo,
            .alpha_mode = .auto,
            .usage = wgpu.TextureUsage.render_attachment | wgpu.TextureUsage.copy_src,
            .view_formats = &[_]wgpu.TextureFormat{swapchain_format},
        };
        self.swapchain.config = @constCast(&config);
        self.swapchain.surface.configure(self.swapchain.config);

        return self;
    }

    // free context resources
    // this kills the render loop
    pub fn release(self: *Context) void {
        if (self.swapchain.surface != undefined) {
            self.swapchain.surface.release();
        }
        if (self.queue != undefined) {
            self.queue.release();
        }
        if (self.device != undefined) {
            self.device.release();
        }
        if (self.adapter != undefined) {
            self.adapter.release();
        }
        if (self.instance != undefined) {
            self.instance.release();
        }
        self.window.destroy();
    }
};

// --- Default Callbacks ---

// Simple key callback to print a global report when the 'r' key is pressed
fn glfw_key_callback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = scancode;
    _ = mods;
    if (key == glfw.Key.r and (action == glfw.Action.press or action == glfw.Action.repeat)) {
        const self: *Context = glfw.Window.getUserPointer(window, Context) orelse return;
        var report: wgpu.GlobalReport = undefined;
        self.instance.generateReport(&report);
        print_global_report(report);
    }
    if (key == glfw.Key.escape and action == glfw.Action.press) {
        glfw.Window.setShouldClose(window, true);
    } else if (key == glfw.Key.q and action == glfw.Action.press) {
        glfw.Window.setShouldClose(window, true);
    }
}

// --- Debugging Helpers ---

// Print a registry report
pub fn print_registry_report(report: wgpu.RegistryReport, prefix: []const u8) void {
    std.debug.print("{s}num_allocated={d}\n", .{ prefix, report.num_allocated });
    std.debug.print("{s}num_kept_from_user={d}\n", .{ prefix, report.num_kept_from_user });
    std.debug.print("{s}num_released_from_user={d}\n", .{ prefix, report.num_released_from_user });
    std.debug.print("{s}num_errors={d}\n", .{ prefix, report.num_error });
    std.debug.print("{s}element_size={d}\n", .{ prefix, report.element_size });
}

// Print a hub report
pub fn print_hub_report(report: wgpu.HubReport, comptime prefix: []const u8) void {
    print_registry_report(report.adapters, prefix ++ "adapter.");
    print_registry_report(report.devices, prefix ++ "device.");
    print_registry_report(report.queues, prefix ++ "queue.");
    print_registry_report(report.pipeline_layouts, prefix ++ "pipelineLayout.");
    print_registry_report(report.shader_modules, prefix ++ "shaderModule.");
    print_registry_report(report.bind_group_layouts, prefix ++ "bindGroupLayout.");
    print_registry_report(report.bind_groups, prefix ++ "bindGroup.");
    print_registry_report(report.command_buffers, prefix ++ "commandBuffer.");
    print_registry_report(report.render_bundles, prefix ++ "renderBundle.");
    print_registry_report(report.render_pipelines, prefix ++ "renderPipeline.");
    print_registry_report(report.compute_pipelines, prefix ++ "computePipeline.");
    print_registry_report(report.query_sets, prefix ++ "querySet.");
    print_registry_report(report.textures, prefix ++ "texture.");
    print_registry_report(report.texture_views, prefix ++ "textureView.");
    print_registry_report(report.samplers, prefix ++ "sampler.");
}

// Print a report of the global state of the WebGPU instance
pub fn print_global_report(report: wgpu.GlobalReport) void {
    std.debug.print("struct GlobalReport [\n", .{});
    print_registry_report(report.surfaces, "\tsurfaces.");

    switch (report.backend_type) {
        .d3d12 => {
            print_hub_report(report.dx12, "\td3d12.");
        },
        .metal => {
            print_hub_report(report.metal, "\tmetal.");
        },
        .vulkan => {
            print_hub_report(report.vulkan, "\tvulkan.");
        },
        .opengl => {
            print_hub_report(report.gl, "\tgl.");
        },
        else => {
            std.debug.print("invalid backend_type={x:.8}\n", .{@intFromEnum(report.backend_type)});
        },
    }

    std.debug.print("]\n", .{});
}

// Print adapter info
pub fn print_adapter_info(adapter: *wgpu.Adapter) void {
    var info: wgpu.AdapterProperties = undefined;
    wgpu.Adapter.getProperties(adapter, &info);
    std.debug.print("Adapter Info: [\n", .{});
    std.debug.print("\tname={s}\n", .{info.name});
    std.debug.print("\tdesc={s}\n", .{info.driver_description});
    std.debug.print("\tvendor={s}\n", .{info.vendor_name});
    std.debug.print("\tvendor_id={d}\n", .{info.vendor_id});
    std.debug.print("\tdevice_id={d}\n", .{info.device_id});
    std.debug.print("\tarchitecture={?s}\n", .{info.architecture});
    std.debug.print("\tbackend_type={}\n", .{info.backend_type});
    std.debug.print("]\n", .{});
}
