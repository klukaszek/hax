// hax.zig: A spiritual successor to Nano.c
// Author: Kyle Lukaszek
// Made Possible By: mach-glfw and wgpu-native-zig
// License: MIT & Apache-2.0

const std = @import("std");
const wgpu = @import("wgpu");
const glfw = @import("mach-glfw");
const builtin = @import("builtin");
const atomic = @import("std").atomic;

// --- Error Enum ---
pub const HaxError = error{
    NoAdapter,
    NoDevice,
    UnsupportedShaderFileType,
};

// --- Structs ---
pub const ContextDescriptor = struct {
    width: u32 = 640,
    height: u32 = 480,
    msaa_samples: u8 = 1,
    title: ?[*:0]const u8 = "hax",
};

pub const ProgramDescriptor = struct {
    init: fn () void = undefined,
    update: fn () void = undefined,
    draw: fn () void = undefined,
    cleanup: fn () void = undefined,
};

// --- Color Target Namespace ---
// This namespace is used to create a default color target for a render pass.
pub const ColorTarget = struct {
    // This is a convenience declaration for not having to write a default color target.
    pub const default: [1]wgpu.ColorTargetState = [_]wgpu.ColorTargetState{
        wgpu.ColorTargetState{
            .format = wgpu.TextureFormat.bgra8_unorm_srgb,
            .blend = &wgpu.BlendState{
                .color = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .one,
                    .dst_factor = .zero,
                },
                .alpha = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .one,
                    .dst_factor = .zero,
                },
            },
            .write_mask = wgpu.ColorWriteMask.all,
        },
    };
};

// --- Color Attachment Namespace ---
// This namespace is used to create a default color attachment for a render pass.
// Perhaps in the future, this will be expanded to include more complex color attachments,
// but really this is just a convenience function for now.
pub const ColorAttachment = struct {
    pub fn default(view: *wgpu.TextureView, resolve: ?*wgpu.TextureView) [1]wgpu.ColorAttachment {
        return [_]wgpu.ColorAttachment{
            wgpu.ColorAttachment{
                .view = view,
                .resolve_target = resolve,
                .loap_op = .clear,
                .store_op = .store,
                .clear_value = wgpu.Color{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
            },
        };
    }
};

// -- Swapchain / Surface Namespace --

pub const Swapchain = struct {
    parent: *Context = undefined,
    surface: *wgpu.Surface = undefined,
    config: wgpu.SurfaceConfiguration = undefined,
    in_flight: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    depth_stencil_texture: *wgpu.Texture = undefined,
    depth_stencil_view: *wgpu.TextureView = undefined,

    msaa_texture: *wgpu.Texture = null,
    msaa_view: *wgpu.TextureView = null,

    // Configure our WebGPU surface for the target platform. Mac OS X is not supported yet, I need to write a C++ wrapper.
    pub fn configureForPlatform(ctx: *Context) void {
        // Check GLFW platform and create the appropriate surface for WebGPU
        switch (glfw.getPlatform()) {
            .x11 => {
                if (builtin.os.tag == .linux) {
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
                }
            },
            .wayland => {
                if (builtin.os.tag == .linux) {
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
                }
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
                        return;
                    };
                    ctx.swapchain.surface = ctx.instance.createSurface(&wgpu.SurfaceDescriptor{
                        .next_in_chain = @ptrCast(&wgpu.SurfaceDescriptorFromWindowsHWND{
                            .chain = wgpu.ChainedStruct{
                                .s_type = wgpu.SType.surface_descriptor_from_windows_hwnd,
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

    pub fn resize(self: *Swapchain, width: u32, height: u32) void {
        self.config.width = width;
        self.config.height = height;
        self.parent.desc.width = width;
        self.parent.desc.height = height;
        std.debug.print("Window size: {d}x{d}\n", .{ width, height });

        Swapchain.configureForPlatform(self.parent);
        self.createDepthTexture(wgpu.TextureFormat.depth24_plus_stencil8);
        self.createMSAATexture();
        self.reconfigure();
    }

    // Reconfigure our surface when needed.
    pub fn reconfigure(self: *Swapchain) void {
        self.surface.unconfigure();
        self.surface.configure(&self.config);
    }

    pub fn present(self: *Swapchain) void {
        self.in_flight.store(false, .seq_cst);
        self.surface.present();
    }

    // Acquire a surface texture from the swapchain for the next frame
    pub fn acquireRenderView(self: *Swapchain) *wgpu.TextureView {
        self.in_flight.store(true, .seq_cst);
        if (self.parent.desc.msaa_samples > 1) {
            return self.msaa_view;
        }

        // Acquire the next swapchain texture
        var surface_texture: wgpu.SurfaceTexture = undefined;
        self.surface.getCurrentTexture(&surface_texture);
        const stat = wgpu.GetCurrentTextureStatus;
        switch (surface_texture.status) {
            stat.success => {},
            stat.timeout, stat.outdated, stat.lost => {
                std.debug.print("Surface texture status: {}\n", .{surface_texture.status});
                self.reconfigure();
            },
            else => {
                std.debug.print("Surface texture error: {}\n", .{surface_texture.status});
            },
        }

        return surface_texture.texture.createView(null).?;
    }

    pub fn acquireResolveView(self: *Swapchain) ?*wgpu.TextureView {
        self.in_flight.store(true, .seq_cst);
        if (self.parent.desc.msaa_samples == 1) {
            return null;
        }
        var surface_texture: wgpu.SurfaceTexture = undefined;
        self.surface.getCurrentTexture(&surface_texture);
        const stat = wgpu.GetCurrentTextureStatus;
        switch (surface_texture.status) {
            stat.success => {},
            stat.timeout, stat.outdated, stat.lost => {
                std.debug.print("Surface texture status: {}\n", .{surface_texture.status});
                self.reconfigure();
            },
            else => {
                std.debug.print("Surface texture error: {}\n", .{surface_texture.status});
            },
        }

        return surface_texture.texture.createView(null).?;
    }

    pub fn createDepthTexture(self: *Swapchain, format: ?wgpu.TextureFormat) void {
        const fmt = format orelse wgpu.TextureFormat.depth24_plus_stencil8;
        const dimensions = self.parent.window.getSize();
        const depth_stencil_texture = self.parent.device.createTexture(&wgpu.TextureDescriptor{
            .size = wgpu.Extent3D{ .width = dimensions.width, .height = dimensions.height, .depth_or_array_layers = 1 },
            .mip_level_count = 1,
            .sample_count = self.parent.desc.msaa_samples,
            .dimension = .@"2d",
            .format = fmt,
            .usage = wgpu.TextureUsage.render_attachment,
            .label = "Depth Stencil Texture",
        }).?;
        self.depth_stencil_texture = depth_stencil_texture;
        self.depth_stencil_view = depth_stencil_texture.createView(null).?;
    }

    pub fn createMSAATexture(self: *Swapchain) void {
        const dimensions = self.parent.window.getSize();
        const msaa_texture = self.parent.device.createTexture(&wgpu.TextureDescriptor{
            .size = wgpu.Extent3D{ .width = dimensions.width, .height = dimensions.height, .depth_or_array_layers = 1 },
            .mip_level_count = 1,
            .sample_count = self.parent.desc.msaa_samples,
            .dimension = .@"2d",
            .format = wgpu.TextureFormat.bgra8_unorm_srgb,
            .usage = wgpu.TextureUsage.render_attachment,
            .label = "MSAA Texture",
        }).?;
        self.msaa_texture = msaa_texture;
        self.msaa_view = msaa_texture.createView(null).?;
    }

    pub fn release(self: *Swapchain) void {
        std.debug.print("Freeing Swapchain\n", .{});
        // if (self.surface != undefined) {
        std.debug.print("\tReleasing surface\n", .{});
        self.surface.release();
        // }
        // if (self.msaa_texture != undefined) {
        std.debug.print("\tReleasing MSAA texture\n", .{});
        self.msaa_texture.release();
        // }
        // if (self.depth_stencil_texture != undefined) {
        std.debug.print("\tReleasing depth stencil\n", .{});
        self.depth_stencil_texture.release();
        // }
        // if (self.depth_stencil_view != undefined) {
        std.debug.print("\tReleasing depth stencil view\n", .{});
        self.depth_stencil_view.release();
        // }
    }
};

// --- Shader Namespace ---
// This namespace is used to create shader modules from SPIR-V or WGSL code.
// Future versions may load Slang from .so and turn any passed shader into SPIR-V.
pub const Shader = struct {
    pub fn createWgslModule(ctx: *Context, code: []const u8) *wgpu.ShaderModule {
        return ctx.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .code = @ptrCast(code),
            .label = "wgsl_module",
        })).?;
    }

    pub fn createSpirvModule(ctx: *Context, code: []const u8) *wgpu.ShaderModule {
        const spv_code_u32: [*]const u32 = @ptrCast(@alignCast(code.ptr));
        return ctx.device.createShaderModule(&wgpu.shaderModuleSPIRVDescriptor(.{
            .code = spv_code_u32,
            .label = "spirv_module",
            .code_size = @intCast(code.len / 4),
        })).?;
    }

    pub fn createModuleFromFile(ctx: *Context, comptime path: []const u8) !*wgpu.ShaderModule {
        const file_contents = @embedFile(path);
        if (std.mem.endsWith(u8, path, ".spv")) {
            return Shader.createSpirvModule(ctx, file_contents);
        } else if (std.mem.endsWith(u8, path, ".wgsl")) {
            return Shader.create_wgsl_module(ctx, file_contents);
        } else {
            std.log.err("Unsupported shader file type: {s}\n", .{path});
            return HaxError.UnsupportedShaderFileType;
        }
    }
};

// --- Context Namespace ---
// This namespace is used to create a WebGPU context and manage the resources associated with it.
// You can think of this as a wrapper around the WebGPU API that makes it easier to use.
// It still makes use of the raw WebGPU API, but it abstracts away some of the more annoying parts.
pub const Context = struct {
    window: glfw.Window = undefined,
    swapchain: Swapchain = {},
    instance: *wgpu.Instance = undefined,
    adapter: *wgpu.Adapter = undefined,
    device: *wgpu.Device = undefined,
    queue: *wgpu.Queue = undefined,
    desc: ContextDescriptor = undefined,

    // Initialize the context
    pub fn initialize(desc: *const ContextDescriptor) HaxError!Context {
        if (!glfw.init(.{})) {
            std.log.err("Failed to initialize GLFW: {?s}\n", .{glfw.getErrorString()});
            std.process.exit(1);
        }

        var self: Context = undefined;
        self.desc = ContextDescriptor{
            .width = desc.width,
            .height = desc.height,
            .msaa_samples = desc.msaa_samples,
            .title = desc.title,
        };

        std.debug.print("width={d} height={d}\n", .{ self.desc.width, self.desc.height });

        // Create our WebGPU instance
        var instance = wgpu.Instance.create(null).?;
        self.instance = instance;

        // Create a GLFW window with no API context
        const hints: glfw.Window.Hints = .{
            .client_api = .no_api,
            .resizable = true,
            .visible = true,
            .samples = desc.msaa_samples,
        };
        const window: glfw.Window = glfw.Window.create(desc.width, desc.height, desc.title.?, null, null, hints) orelse {
            std.log.err("Failed to initialize GLFW window: {?s}\n", .{glfw.getErrorString()});
            std.process.exit(1);
        };
        self.window = window;

        // Set the self struct as the user pointer of the window
        defer glfw.Window.setKeyCallback(window, glfw_key_callback);
        defer glfw.Window.setFramebufferSizeCallback(window, glfw_framebuffer_size_callback);
        defer glfw.makeContextCurrent(window);

        std.debug.print("Init Window: {p}, Size: {d}x{d}\n", .{ self.window.handle, self.window.getSize().width, self.window.getSize().height });

        Swapchain.configureForPlatform(&self);

        // Request a high-performance adapter now that we have a surface
        const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{
            // .power_preference = .high_performance,
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
        self.swapchain.config = wgpu.SurfaceConfiguration{
            .device = device,
            .width = dimensions.width,
            .height = dimensions.height,
            .format = swapchain_format,
            .present_mode = .fifo,
            .alpha_mode = .auto,
            .usage = wgpu.TextureUsage.render_attachment | wgpu.TextureUsage.copy_src,
            .view_formats = &[_]wgpu.TextureFormat{swapchain_format},
        };
        self.swapchain.reconfigure();
        self.swapchain.parent = @ptrCast(&self);

        // Create the depth texture
        self.swapchain.createDepthTexture(wgpu.TextureFormat.depth24_plus_stencil8);

        // Create the MSAA texture if needed
        self.swapchain.createMSAATexture();

        return self;
    }

    // free context resources
    // this kills the render loop
    pub fn release(self: *Context) void {
        std.debug.print("Releasing hax context\n", .{});
        self.swapchain.release();
        std.debug.print("Releasing wgpu-native resources\n", .{});
        self.queue.release();
        self.device.release();
        self.adapter.release();
        self.instance.release();
        self.window.destroy();
    }
};

// --- Default Callbacks ---

fn glfw_framebuffer_size_callback(window: glfw.Window, width: u32, height: u32) void {
    const self: *Context = glfw.Window.getUserPointer(window, Context) orelse return;
    self.swapchain.resize(width, height);
}

// Simple key callback to print a global report when the 'r' key is pressed
fn glfw_key_callback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = mods;
    const self: *Context = glfw.Window.getUserPointer(window, Context) orelse return;
    std.debug.print("Key: {s} Action: {}\n", .{ key.getName(scancode).?, action });
    if (key == glfw.Key.r and (action == glfw.Action.press or action == glfw.Action.repeat)) {
        var report: wgpu.GlobalReport = undefined;
        self.instance.generateReport(&report);
        print_global_report(report);
    }
    if (key == glfw.Key.f and (action == glfw.Action.press)) {
        var mon: ?glfw.Monitor = window.getMonitor();
        var video_mode: glfw.VideoMode = undefined;
        if (mon == null) {
            mon = glfw.Monitor.getPrimary();
            video_mode = mon.?.getVideoMode().?;
            window.setMonitor(mon, 0, 0, video_mode.getWidth(), video_mode.getHeight(), video_mode.getRefreshRate());
        } else {
            video_mode = mon.?.getVideoMode().?;
            window.setMonitor(null, 0, 0, 800, 600, 0);
        }
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
