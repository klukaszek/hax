// Simple example of using hax to render a triangle
const std = @import("std");
const hax = @import("hax");
const wgpu = @import("wgpu");
const glfw = @import("mach-glfw");

const shader = @embedFile("triangle.spv");
var ctx: hax.Context = undefined;

// Main function for the example
pub fn main() !void {
    // Initialize our hax context. This will create a window and a swapchain, and initialize the WebGPU API.
    ctx = try hax.Context.initialize(&hax.ContextDescriptor{ .title = "hax: triangle", .width = 800, .height = 600, .msaa_samples = 4 });
    defer ctx.release();
    // Set the swapchain's parent to the context
    ctx.swapchain.parent = @constCast(&ctx);

    glfw.Window.setUserPointer(ctx.window, &ctx);

    const shader_module = hax.Shader.createSpirvModule(&ctx, shader);
    defer shader_module.release();

    const color_targets = &hax.ColorTarget.default;

    // Create the render pipeline
    const pipeline = ctx.device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = shader_module,
            .entry_point = "vertexMain",
        },
        .fragment = &wgpu.FragmentState{ .module = shader_module, .entry_point = "fragmentMain", .target_count = color_targets.len, .targets = color_targets },
        .primitive = wgpu.PrimitiveState{ .topology = .triangle_list },
        .multisample = wgpu.MultisampleState{ .mask = 0xFFFF, .count = ctx.desc.msaa_samples },
    }).?;
    defer pipeline.release();

    var time = std.time.nanoTimestamp();

    // Main program loop
    while (!ctx.window.shouldClose()) {

        // Calculate the time since the last frame
        const now = std.time.nanoTimestamp();
        const res: i128 = now - time;
        const delta = @as(f128, @floatFromInt(res)) / std.time.ns_per_s;
        time = now;

        const fps = 1.0 / delta;

        std.debug.print("Frame time: {d:.2}, FPS: {d:.2}\n", .{ delta * 1000, fps });

        glfw.pollEvents();

        // Acquire the next frame from the context's swapchain
        const frame_view = ctx.swapchain.acquireRenderView();
        const resolve_target = ctx.swapchain.acquireResolveView();
        defer resolve_target.?.release();

        // Create WebGPU Command Encoder
        const encoder: *wgpu.CommandEncoder = ctx.device.createCommandEncoder(&.{
            .label = "hax wgpu Command Encoder",
        }).?;

        // Acquire default color attachment
        const color_attachment = hax.ColorAttachment.default(frame_view, resolve_target);

        // Create render pass
        const render_pass: *wgpu.RenderPassEncoder = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{ .label = "hax wgpu Render Pass", .color_attachment_count = 1, .color_attachments = &color_attachment }).?;
        defer render_pass.release();

        render_pass.setPipeline(pipeline);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();

        // Create a command buffer
        const command_buffer: *wgpu.CommandBuffer = encoder.finish(&wgpu.CommandBufferDescriptor{ .label = "hax wgpu Command Buffer" }).?;
        defer command_buffer.release();

        // Submit the command buffer
        ctx.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});
        ctx.swapchain.present();
    }
}
