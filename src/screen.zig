const gpu = @import("gpu");
const glfw = @import("glfw");
const std = @import("std");
const Window = @import("window.zig");
const This = @This();

instance: *gpu.Instance,
adapter: *gpu.Adapter,
device: *gpu.Device,
queue: *gpu.Queue,
surface: *gpu.Surface,
swapchain: *gpu.SwapChain,
shader: *gpu.ShaderModule,
vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
window_size_buffer: *gpu.Buffer,
display_buffer: *gpu.Buffer,
color_buffer: *gpu.Buffer,
bind_group_layout: *gpu.BindGroupLayout,
bind_group: *gpu.BindGroup,
pipeline: *gpu.RenderPipeline,

bg_color: gpu.Color,

const AdapterWrapper = struct { ?*gpu.Adapter = null };
inline fn RequestAdapterCallback(
    adapter_wrapper: *AdapterWrapper,
    _: gpu.RequestAdapterStatus,
    adapter: ?*gpu.Adapter,
    _: ?[*:0]const u8,
) void {
    adapter_wrapper.*[0] = adapter;
}

pub fn windowResizeCallback(window: glfw.Window, width: u32, height: u32) void {
    const user_pointer = window.getUserPointer([2]*anyopaque) orelse return;
    const this: *This = @ptrCast(@alignCast(user_pointer[0]));

    this.updateWindowSizeBuffer(.{ .width = width, .height = height });
    this.swapchain.release();
    this.createSwapChain(.{ .width = width, .height = height });
}

pub fn windowRefreshCallback(window: glfw.Window) void {
    const user_pointer = window.getUserPointer([2]*anyopaque) orelse return;
    const this: *This = @ptrCast(@alignCast(user_pointer[0]));

    this.draw();
}

fn requestAdapter(this: *This) !void {
    var adapter_wrapper: AdapterWrapper = .{};

    this.instance.requestAdapter(null, &adapter_wrapper, RequestAdapterCallback);

    this.adapter = adapter_wrapper[0] orelse return error.adapter;
}

fn createDevice(this: *This) !void {
    // todo: features necessarie
    this.device = this.adapter.createDevice(null) orelse return error.device;
}

fn createSwapChain(this: *This, size: glfw.Window.Size) void {
    const swapchain_descriptor = gpu.SwapChain.Descriptor{
        .width = size.width,
        .height = size.height,
        .format = .bgra8_unorm,
        .present_mode = .fifo,
        .usage = .{ .render_attachment = true },
    };

    this.swapchain = this.device.createSwapChain(this.surface, &swapchain_descriptor);
}

fn createBuffers(this: *This) void {
    // Vertex buffer
    const vertex_buffer_descriptor = gpu.Buffer.Descriptor{
        .size = 8 * @sizeOf(f32),
        .usage = .{ .copy_dst = true, .vertex = true },
    };

    this.vertex_buffer = this.device.createBuffer(&vertex_buffer_descriptor);
    this.queue.writeBuffer(this.vertex_buffer, 0, &[8]f32{
        -1, -1,
        1,  -1,
        1,  1,
        -1, 1,
    });

    const index_buffer_descriptor = gpu.Buffer.Descriptor{
        .size = 6 * @sizeOf(u16),
        .usage = .{ .copy_dst = true, .index = true },
    };

    this.index_buffer = this.device.createBuffer(&index_buffer_descriptor);
    this.queue.writeBuffer(this.index_buffer, 0, &[6]u16{
        0, 1, 2,
        0, 2, 3,
    });

    // Display size buffer
    const display_size_buffer_descriptor = gpu.Buffer.Descriptor{
        .size = 2 * @sizeOf(f32),
        .usage = .{ .copy_dst = true, .uniform = true },
    };
    this.window_size_buffer = this.device.createBuffer(&display_size_buffer_descriptor);

    // Display buffer
    const display_buffer_descriptor = gpu.Buffer.Descriptor{
        .size = 64 * @sizeOf(u32),
        .usage = .{ .copy_dst = true, .storage = true },
    };
    this.display_buffer = this.device.createBuffer(&display_buffer_descriptor);

    const color_buffer = gpu.Buffer.Descriptor{
        .size = 3 * @sizeOf(f32),
        .usage = .{ .copy_dst = true, .uniform = true },
    };
    this.color_buffer = this.device.createBuffer(&color_buffer);
}

fn updateWindowSizeBuffer(this: This, size: glfw.Window.Size) void {
    this.queue.writeBuffer(this.window_size_buffer, 0, &[_]f32{ @floatFromInt(size.width), @floatFromInt(size.height) });
}

fn writeColorBuffer(this: This, fg_color: gpu.Color) void {
    this.queue.writeBuffer(this.color_buffer, 0, &[_]f32{
        @floatCast(fg_color.r),
        @floatCast(fg_color.g),
        @floatCast(fg_color.b),
    });
}

pub fn writeDisplayBuffer(this: This, cpu_display: [64]u32) void {
    this.queue.writeBuffer(this.display_buffer, 0, &cpu_display);
}

fn createBindGroup(this: *This) void {
    const bind_group_layout_entries = [_]gpu.BindGroupLayout.Entry{
        gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, 2 * @sizeOf(f32)),
        gpu.BindGroupLayout.Entry.buffer(1, .{ .fragment = true }, .storage, false, 64 * @sizeOf(u32)),
        gpu.BindGroupLayout.Entry.buffer(2, .{ .fragment = true }, .uniform, false, 3 * @sizeOf(f32)),
    };

    const bind_group_layout_descriptor = gpu.BindGroupLayout.Descriptor.init(.{ .entries = &bind_group_layout_entries });

    this.bind_group_layout = this.device.createBindGroupLayout(&bind_group_layout_descriptor);

    const bind_group = [_]gpu.BindGroup.Entry{
        gpu.BindGroup.Entry.buffer(0, this.window_size_buffer, 0, 2 * @sizeOf(f32)),
        gpu.BindGroup.Entry.buffer(1, this.display_buffer, 0, 64 * @sizeOf(u32)),
        gpu.BindGroup.Entry.buffer(2, this.color_buffer, 0, 3 * @sizeOf(f32)),
    };

    const binding_group_descriptor = gpu.BindGroup.Descriptor.init(.{
        .layout = this.bind_group_layout,
        .entries = &bind_group,
    });
    this.bind_group = this.device.createBindGroup(&binding_group_descriptor);
}

fn createPipeline(this: *This) void {
    const bland_state = gpu.BlendState{
        .color = .{
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
            .operation = .add,
        },
        .alpha = .{
            .src_factor = .zero,
            .dst_factor = .one,
            .operation = .add,
        },
    };

    const color_target_state = gpu.ColorTargetState{
        .format = .bgra8_unorm,
        .blend = &bland_state,
    };

    const fragment_state = gpu.FragmentState{
        .module = this.shader,
        .entry_point = "fs_main",
        .target_count = 1,
        .targets = &[_]gpu.ColorTargetState{color_target_state},
    };

    const vertex_attribute = gpu.VertexAttribute{
        .shader_location = 0,
        .format = .float32x2,
        .offset = 0,
    };

    const vertex_buffer_layout = gpu.VertexBufferLayout{
        .attribute_count = 1,
        .attributes = &[_]gpu.VertexAttribute{vertex_attribute},
        .array_stride = 2 * @sizeOf(f32),
        .step_mode = .vertex,
    };

    const pipeline_layout_descriptor = gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &[_]*gpu.BindGroupLayout{this.bind_group_layout},
    });

    const pipeline_layout = this.device.createPipelineLayout(&pipeline_layout_descriptor);

    const render_pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .vertex = .{
            .module = this.shader,
            .entry_point = "vs_main",
            .buffer_count = 1,
            .buffers = &[_]gpu.VertexBufferLayout{vertex_buffer_layout},
        },
        .fragment = &fragment_state,
        .layout = pipeline_layout,
    };

    this.pipeline = this.device.createRenderPipeline(&render_pipeline_descriptor);
}

pub fn init(allocator: std.mem.Allocator, window: Window, colors: [2]gpu.Color) !This {
    try gpu.Impl.init(allocator, .{});

    var ret: This = undefined;

    ret.bg_color = colors[0];

    const window_size = window.getSize();

    ret.instance = gpu.createInstance(null) orelse return error.instance;
    try ret.requestAdapter();
    try ret.createDevice();
    ret.queue = ret.device.getQueue();
    ret.surface = window.createSurface(ret.instance);

    ret.createSwapChain(window_size);
    ret.shader = ret.device.createShaderModuleWGSL(null, @embedFile("shader.wgsl"));
    ret.createBuffers();
    ret.updateWindowSizeBuffer(window_size);
    ret.writeColorBuffer(colors[1]);
    ret.createBindGroup();
    ret.createPipeline();

    return ret;
}

pub fn deinit(this: This) void {
    this.pipeline.release();
    this.bind_group_layout.release();
    this.bind_group.release();
    this.color_buffer.destroy();
    this.color_buffer.reference();
    this.display_buffer.destroy();
    this.display_buffer.release();
    this.window_size_buffer.destroy();
    this.window_size_buffer.release();
    this.index_buffer.destroy();
    this.index_buffer.release();
    this.vertex_buffer.destroy();
    this.vertex_buffer.release();
    this.shader.release();
    this.swapchain.release();
    this.surface.release();
    this.queue.release();
    this.device.release();
    this.adapter.release();
    this.instance.release();
}

pub fn draw(this: This) void {
    const current_texture = this.swapchain.getCurrentTexture() orelse return;
    const current_texture_view = current_texture.createView(null);

    const encoder = this.device.createCommandEncoder(null);

    const color_attachments = [_]gpu.RenderPassColorAttachment{.{
        .view = current_texture_view,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = this.bg_color,
    }};

    const render_pass_descriptor = gpu.RenderPassDescriptor{
        .color_attachment_count = color_attachments.len,
        .color_attachments = &color_attachments,
    };

    const render_pass = encoder.beginRenderPass(&render_pass_descriptor);
    render_pass.setPipeline(this.pipeline);
    render_pass.setVertexBuffer(0, this.vertex_buffer, 0, 8 * @sizeOf(f32));
    render_pass.setIndexBuffer(this.index_buffer, .uint16, 0, 6 * @sizeOf(u16));
    render_pass.setBindGroup(0, this.bind_group, null);
    render_pass.drawIndexed(6, 1, 0, 0, 0);
    render_pass.end();
    render_pass.release();

    current_texture_view.release();
    current_texture.release();

    const command = encoder.finish(null);
    encoder.release();
    this.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    this.swapchain.present();
}
