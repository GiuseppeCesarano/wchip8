const Chip8 = @import("chip8.zig");
const Window = @import("window.zig");
const Screen = @import("screen.zig");
const gpu = @import("gpu");
const std = @import("std");
const glfw = @import("glfw");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const options = getCommandLineOptions(allocator);

    const rom = try std.fs.cwd().openFile(options.rom_path, .{});

    const window = try Window.init();
    defer window.deinit();

    var screen = try Screen.init(allocator, window, .{ options.bg_color, options.fg_color });
    defer screen.deinit();

    var chip = try Chip8.init(rom.reader().any(), @intCast(std.time.timestamp()));

    rom.close();

    var pointers_wrapper = [2]*anyopaque{ &screen, &chip.keys };
    window.setCallbacks(&pointers_wrapper, Screen.windowResizeCallback, handleKeys, Screen.windowRefreshCallback);

    const cycle_target_time = @divTrunc(std.time.ns_per_s, 500);
    var cycle_timer = try std.time.Timer.start();

    var cycle_count: u5 = 0;
    var cycle_count_overflow: u1 = 0;

    while (!window.shouldClose()) : ({
        const res = @addWithOverflow(cycle_count, 1 - cycle_count_overflow);
        cycle_count = res[0];
        cycle_count_overflow = res[1];
    }) {
        window.handleEvents();

        chip.cycle();

        const is_60Hz = cycle_count_overflow == 0 and cycle_count % 8 == 0;
        chip.delay_timer -|= @intFromBool(is_60Hz);
        chip.sound_timer -|= @intFromBool(is_60Hz);

        if (chip.isDrawNeeded() and is_60Hz) {
            screen.writeDisplayBuffer(chip.display);
            screen.draw();

            chip.clearDrawNeeded();
        }

        std.time.sleep(cycle_target_time -| cycle_timer.lap());
    }

    _ = gpa.deinit();
}

fn handleKeys(window: glfw.Window, key: glfw.Key, _: i32, action: glfw.Action, _: glfw.Mods) void {
    const user_pointer = window.getUserPointer([2]*anyopaque) orelse return;
    const chip_keys: *u16 = @ptrCast(@alignCast(user_pointer[1]));

    const shift: u4 = switch (key) {
        .x => 15,
        .one => 14,
        .two => 13,
        .three => 12,
        .q => 11,
        .w => 10,
        .e => 9,
        .a => 8,
        .s => 7,
        .d => 6,
        .z => 5,
        .c => 4,
        .four => 3,
        .r => 2,
        .f => 1,
        .v => 0,
        else => return,
    };

    if (action == .release) {
        chip_keys.* &= ~(@as(u16, 1) << shift);
    } else {
        chip_keys.* |= (@as(u16, 1) << shift);
    }
}

const Options = struct {
    rom_path: [:0]const u8,
    bg_color: gpu.Color,
    fg_color: gpu.Color,
};

fn getCommandLineOptions(allocator: std.mem.Allocator) Options {
    var args = std.process.argsWithAllocator(allocator) catch return .{};
    _ = args.skip(); // skip program name

    const default_bg_color = gpu.Color{ .r = 0.15, .b = 0.15, .g = 0.15, .a = 1 };
    const default_fg_color = gpu.Color{ .r = 0.85, .b = 0.85, .g = 0.85, .a = 1 };

    return Options{
        .rom_path = args.next() orelse "rom",
        .bg_color = if (args.next()) |bg_color| convertColor(bg_color) catch default_bg_color else default_bg_color,
        .fg_color = if (args.next()) |fg_color| convertColor(fg_color) catch default_fg_color else default_fg_color,
    };
}

fn convertColor(color: [:0]const u8) !gpu.Color {
    if (color.len != 6) {
        return error.colorSizeDontMatch;
    }

    return gpu.Color{
        .r = @as(f64, @floatFromInt(try std.fmt.parseInt(u8, color[0..2], 16))) / 255.0,
        .g = @as(f64, @floatFromInt(try std.fmt.parseInt(u8, color[2..4], 16))) / 255.0,
        .b = @as(f64, @floatFromInt(try std.fmt.parseInt(u8, color[4..6], 16))) / 255.0,
        .a = 1,
    };
}
