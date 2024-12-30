// Simple example of using hax to render a triangle
const std = @import("std");
const wgpu = @import("wgpu");
const glfw = @import("mach-glfw");
const hax = @import("hax.zig");

// Main function for the example
pub fn main() !void {
    var ctx: hax.Context = undefined;

    // Initialize our hax context. This will create a window and a swapchain, and initialize the WebGPU API.
    ctx = try hax.Context.initialize(@constCast(&hax.ContextDescriptor{ .title = "hax: triangle" }));
    defer ctx.release();

    const shader_module = ctx.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("./triangle.wgsl"),
    })).?;
    defer shader_module.release();

    // Define colour target for swapchain texture
    const color_targets = &[_]wgpu.ColorTargetState{
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

    // Create the render pipeline
    const pipeline = ctx.device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = shader_module,
            .entry_point = "vertexMain",
        },
        .fragment = &wgpu.FragmentState{ .module = shader_module, .entry_point = "fragmentMain", .target_count = color_targets.len, .targets = color_targets.ptr },
        .primitive = wgpu.PrimitiveState{ .topology = .triangle_list },
        .multisample = wgpu.MultisampleState{ .mask = 0xFFFF },
    }).?;
    defer pipeline.release();

    // Main program loop
    while (!ctx.window.shouldClose()) {
        glfw.pollEvents();

        // Acquire the next frame from the context's swapchain
        const frame: *const wgpu.SurfaceTexture = &hax.Swapchain.acquire_next_frame(&ctx);
        defer frame.texture.release();

        // Create texture view
        const frame_view: *wgpu.TextureView = frame.texture.createView(null).?;
        defer frame_view.release();
        // Create WebGPU Command Encoder
        const encoder: *wgpu.CommandEncoder = ctx.device.createCommandEncoder(&.{
            .label = "hax wgpu Command Encoder",
        }).?;

        // Create render pass
        const render_pass: *wgpu.RenderPassEncoder = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{ .label = "hax wgpu Render Pass", .color_attachment_count = 1, .color_attachments = &[_]wgpu.ColorAttachment{
            wgpu.ColorAttachment{
                .view = frame_view,
                .resolve_target = null,
                .loap_op = .clear,
                .store_op = .store,
                .clear_value = wgpu.Color{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
            },
        } }).?;
        defer render_pass.release();

        render_pass.setPipeline(pipeline);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();

        // Create a command buffer
        const command_buffer: *wgpu.CommandBuffer = encoder.finish(&wgpu.CommandBufferDescriptor{ .label = "hax wgpu Command Buffer" }).?;
        defer command_buffer.release();

        // Submit the command buffer
        ctx.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});
        ctx.swapchain.surface.present();
    }
}
