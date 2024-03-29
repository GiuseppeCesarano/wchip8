const std = @import("std");
const glfw = @import("glfw");
const This = @This();
const gpu = @import("gpu");

window: glfw.Window,

pub fn init() !This {
    if (!glfw.init(.{})) return glfw.mustGetErrorCode();

    return This{
        .window = glfw.Window.create(1024, 720, "wchip8", null, null, .{ .client_api = .no_api }) orelse return glfw.mustGetErrorCode(),
    };
}

pub fn deinit(this: This) void {
    this.window.destroy();
    glfw.terminate();
}

pub fn shouldClose(this: This) bool {
    return this.window.shouldClose();
}

pub fn handleEvents(this: This) void {
    glfw.pollEvents();
    _ = this;
}

pub fn getSize(this: This) glfw.Window.Size {
    return this.window.getFramebufferSize();
}

pub fn createSurface(this: This, instance: *gpu.Instance) *gpu.Surface {
    const glfw_native = glfw.Native(.{ .x11 = true });

    return instance.createSurface(&gpu.Surface.Descriptor{
        .next_in_chain = .{
            .from_xlib_window = &.{
                .display = glfw_native.getX11Display(),
                .window = glfw_native.getX11Window(this.window),
            },
        },
    });
}

pub fn setCallbacks(
    this: This,
    user_pointer: *[2]*anyopaque,
    comptime resize_callback: ?fn (window: glfw.Window, width: u32, height: u32) void,
    comptime key_callback: ?fn (window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void,
    comptime refresh_callback: ?fn (window: glfw.Window) void,
) void {
    this.window.setUserPointer(@ptrCast(user_pointer));
    this.window.setFramebufferSizeCallback(resize_callback);
    this.window.setKeyCallback(key_callback);
    this.window.setRefreshCallback(refresh_callback);
}
