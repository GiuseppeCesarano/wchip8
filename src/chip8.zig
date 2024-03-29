const std = @import("std");
const This = @This();

const program_entrypoint = 0x200;

const font = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

program_counter: u16,
ram: [4 * 1024]u8,
registers: [16]u8,
index: u16,

delay_timer: u8,
sound_timer: u8,

stack: [16]u16,
stack_pointer: u8,

display: [64]u32,
keys: u16,

generator: std.Random.Pcg,

const keys_statuses_location = font.len;
const keys_statuses_type: type = [2]u16;

const is_draw_needed_location = keys_statuses_location + @sizeOf(keys_statuses_type) + 2;

pub fn init(program_reader: std.io.AnyReader, seed: u64) !This {
    var instance = std.mem.zeroInit(This, .{ .program_counter = program_entrypoint, .ram = undefined, .generator = std.Random.Pcg.init(seed) });

    std.mem.copyForwards(u8, instance.ram[0..font.len], &font);

    const keys_statuses: *keys_statuses_type = @ptrCast(@alignCast(&instance.ram[keys_statuses_location]));
    keys_statuses[0] = std.math.maxInt(@TypeOf(keys_statuses[0]));
    keys_statuses[1] = 0;

    _ = try program_reader.readAll(instance.ram[program_entrypoint..]);

    return instance;
}

pub fn cycle(this: *This) void {
    const operation: u16 = @as(u16, this.ram[this.program_counter]) << 8 | this.ram[this.program_counter + 1];

    switch (operation >> 12) {
        0x0 => {
            switch (operation) {

                // 00E0 - CLS
                0x00E0 => {
                    this.set_draw_needed();
                    for (&this.display) |*row| {
                        row.* = 0;
                    }
                },

                // 00EE - RET
                0x00EE => {
                    this.stack_pointer -= 1;
                    this.program_counter = this.stack[this.stack_pointer];
                },

                // 0nnn - SYS addr
                else => {
                    // This instruction is only used on the old computers on which Chip-8 was originally implemented. It is ignored by modern interpreters.
                },
            }
            this.program_counter += 2;
        },

        // 1nnn - JP addr
        0x1 => {
            this.program_counter = operation & 0x0FFF;
        },

        // 2nnn - CALL addr
        0x2 => {
            this.stack[this.stack_pointer] = this.program_counter;
            this.stack_pointer += 1;
            this.program_counter = operation & 0x0FFF;
        },

        // 3xkk - SE Vx, byte
        0x3 => {
            const x = (operation >> 8) & 0xF;
            this.program_counter += if (this.registers[x] == (operation & 0x00FF)) 4 else 2;
        },

        // 4xkk - SNE Vx, byte
        0x4 => {
            const x = (operation >> 8) & 0xF;
            this.program_counter += if (this.registers[x] != (operation & 0x00FF)) 4 else 2;
        },

        // 5xy0 - SE Vx, Vy
        0x5 => {
            const x = (operation >> 8) & 0xF;
            const y = (operation >> 4) & 0xF;

            this.program_counter += if (this.registers[x] == this.registers[y]) 4 else 2;
        },

        // 6xkk - LD Vx, byte
        0x6 => {
            const x = (operation >> 8) & 0xF;
            this.registers[x] = @truncate(operation & 0xFF);

            this.program_counter += 2;
        },

        // 7xkk - ADD Vx, byte
        0x7 => {
            const x = (operation >> 8) & 0xF;
            this.registers[x] = @addWithOverflow(this.registers[x], @as(u8, @truncate(operation & 0xFF)))[0];

            this.program_counter += 2;
        },

        0x8 => {
            const x = (operation >> 8) & 0xF;
            const y = (operation >> 4) & 0xF;

            switch (operation & 0xF) {

                //  8xy0 - LD Vx, Vy
                0x0 => {
                    this.registers[x] = this.registers[y];
                    this.registers[0xF] = 0;
                },

                // 8xy1 - OR Vx, Vy
                0x1 => {
                    this.registers[x] |= this.registers[y];
                    this.registers[0xF] = 0;
                },

                // 8xy2 - AND Vx, Vy
                0x2 => {
                    this.registers[x] &= this.registers[y];
                    this.registers[0xF] = 0;
                },

                // 8xy3 - XOR Vx, Vy
                0x3 => {
                    this.registers[x] ^= this.registers[y];
                    this.registers[0xF] = 0;
                },

                // 8xy4 - ADD Vx, Vy
                0x4 => {
                    const res = @addWithOverflow(this.registers[x], this.registers[y]);

                    this.registers[x] = res[0];
                    this.registers[0xF] = res[1];
                },

                // 8xy5 - SUB Vx, Vy
                0x5 => {
                    const sub_res = @subWithOverflow(this.registers[x], this.registers[y]);

                    this.registers[x] = sub_res[0];
                    this.registers[0xF] = ~sub_res[1];
                },

                // 8xy6 - SHR Vx {, Vy}
                0x6 => {
                    const flag = this.registers[y] & 1;

                    this.registers[x] = this.registers[y] >> 1;
                    this.registers[0xF] = flag;
                },

                // 8xy7 - SUBN Vx, Vy
                0x7 => {
                    const sub_res = @subWithOverflow(this.registers[y], this.registers[x]);

                    this.registers[x] = sub_res[0];
                    this.registers[0xF] = ~sub_res[1];
                },

                // 8xyE - SHL Vx {, Vy}
                0xE => {
                    const res = @shlWithOverflow(this.registers[y], 1);

                    this.registers[x] = res[0];
                    this.registers[0xF] = res[1];
                },
                else => {},
            }

            this.program_counter += 2;
        },

        // 9xy0 - SNE Vx, Vy
        0x9 => {
            const x = (operation >> 8) & 0xF;
            const y = (operation >> 4) & 0xF;

            this.program_counter += if (this.registers[x] != this.registers[y]) 4 else 2;
        },

        // Annn - LD I, addr
        0xA => {
            this.index = operation & 0x0FFF;

            this.program_counter += 2;
        },

        // Bnnn - JP V0, addr
        0xB => {
            this.program_counter = (operation & 0x0FFF) + this.registers[0];
        },

        // Cxkk - RND Vx, byte
        0xC => {
            const x = (operation >> 8) & 0xF;
            this.registers[x] = @truncate(this.generator.random().int(u8) % (operation & 0x00FF));

            this.program_counter += 2;
        },

        0xD => {
            this.set_draw_needed();

            this.registers[0xF] = 0;

            const x_start = this.registers[(operation >> 8) & 0xF];
            const y_start = this.registers[(operation >> 4) & 0xF];
            const n = operation & 0xF;

            for (0..n) |y| {
                const coord_y = (y_start + y) % 32;

                for (0..8) |x| {
                    if ((this.ram[this.index + y] & (@as(u8, 0x80) >> @intCast(x))) != 0) {
                        const coord_x = (x_start + x) % 64;
                        const index = coord_y * 2 + coord_x / 32;
                        const mask = @as(u32, 1) << @intCast(31 - (coord_x % 32));

                        this.display[index] ^= mask;
                        this.registers[0x0F] = if (this.display[index] & mask == 0) 1 else this.registers[0x0F];
                    }
                }
            }

            this.program_counter += 2;
        },

        // Ex9E - SKP Vx
        // ExA1 - SKNP Vx
        0xE => {
            const x = (operation >> 8) & 0xF;
            const mode = operation & 0x00FF;
            const shift = (@bitSizeOf(@TypeOf(this.keys)) - 1) - @as(u4, @intCast(this.registers[x]));
            const key = ((this.keys >> shift) & 1) == 1;

            this.program_counter += if ((mode == 0x9E and key) or (mode == 0xA1 and !key)) 4 else 2;
        },

        0xF => {
            const x = (operation >> 8) & 0xF;

            switch (operation & 0x00FF) {

                // Fx07 - LD Vx, DT
                0x07 => {
                    this.registers[x] = this.delay_timer;
                },

                // Fx0A - LD Vx, K
                0x0A => {
                    const keys_statuses: *keys_statuses_type = @ptrCast(@alignCast(&this.ram[keys_statuses_location]));

                    if (keys_statuses[0] == std.math.maxInt(@TypeOf(keys_statuses[0]))) {
                        keys_statuses[0] = this.keys;
                    } else {
                        const masked_keys = ~keys_statuses[0] & keys_statuses[1] & ~this.keys;

                        if (masked_keys != 0) {
                            for (0..16) |index| {
                                const shift = (@bitSizeOf(@TypeOf(masked_keys)) - 1) - @as(u4, @intCast(index));

                                if ((masked_keys >> shift) & 1 == 1) {
                                    this.registers[x] = @as(u8, @intCast(index));
                                    break;
                                }
                            }
                            keys_statuses[0] = std.math.maxInt(@TypeOf(keys_statuses[0]));
                            keys_statuses[1] = 0;
                            // Negate the next negation, resulting in a normal
                            // program count increment.
                            this.program_counter += 2;
                        } else {
                            keys_statuses[1] = this.keys;
                        }
                    }

                    // Negate increment at the end of the switch
                    this.program_counter -= 2;
                },

                // Fx15 - LD DT, Vx
                0x15 => {
                    this.delay_timer = this.registers[x];
                },

                // Fx18 - LD ST, Vx
                0x18 => {
                    this.sound_timer = this.registers[x];
                },

                // Fx1E - ADD I, Vx
                0x1E => {
                    this.index += this.registers[x];
                },

                // Fx29 - LD F, Vx
                0x29 => {
                    this.index = x * 5;
                },

                // Fx33 - LD B, Vx
                0x33 => {
                    this.ram[this.index] = @divTrunc(this.registers[x], 100);
                    this.ram[this.index + 1] = @divTrunc(this.registers[x], 10) % 10;
                    this.ram[this.index + 2] = this.registers[x] % 10;
                },

                // Fx55 - LD [I], Vx
                0x55 => {
                    std.mem.copyForwards(u8, this.ram[this.index..], this.registers[0 .. x + 1]);
                    this.index += 1;
                },

                // Fx65 - LD Vx, [I]
                0x65 => {
                    std.mem.copyForwards(u8, &this.registers, this.ram[this.index .. this.index + x + 1]);
                    this.index += 1;
                },
                else => {},
            }

            this.program_counter += 2;
        },
        else => {},
    }
}

fn set_draw_needed(this: *This) void {
    this.ram[is_draw_needed_location] = 1;
}

pub fn is_draw_needed(this: *This) bool {
    return this.ram[is_draw_needed_location] == 1;
}

pub fn clear_draw_needed(this: *This) void {
    this.ram[is_draw_needed_location] = 0;
}

test "chip8" {
    var program_stream = std.io.fixedBufferStream(&[_]u8{0});
    const program_reader = program_stream.reader();

    var chip = try init(&program_reader.any(), 0);
    chip.cycle();

    try std.testing.expect(chip.ram[0] == font[0]);
}
