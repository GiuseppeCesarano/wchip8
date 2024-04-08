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

pub fn init(program_reader: std.io.AnyReader, seed: u64) !This {
    var instance = std.mem.zeroInit(This, .{ .program_counter = program_entrypoint, .ram = undefined });

    instance.generator = std.Random.Pcg.init(seed);

    std.mem.copyForwards(u8, instance.ram[0..font.len], &font);

    const keys_statuses = instance.keysStatuses();
    keys_statuses[0] = std.math.maxInt(@TypeOf(keys_statuses[0]));
    keys_statuses[1] = 0;

    _ = try program_reader.readAll(instance.ram[program_entrypoint..]);

    return instance;
}

pub fn cycle(this: *This) void {
    const operation = this.opcode();

    // TODO: remove all pc increments except for the first one.
    switch (operation) {
        0x0000...0x00DF, 0x00E1...0x00ED, 0x00EF...0x0FFF => this.program_counter += 2,
        0x00E0 => this.cls(),
        0x00EE => this.ret(),
        0x1000...0x1FFF => this.jp_addr(),
        0x2000...0x2FFF => this.call_addr(),
        0x3000...0x3FFF => this.se_vx_byte(),
        0x4000...0x4FFF => this.sne_vx_byte(),
        0x5000...0x5FFF => this.se_vx_vy(),
        0x6000...0x6FFF => this.ld_vx_byte(),
        0x7000...0x7FFF => this.add_vx_byte(),
        0x8000...0x8FFF => {
            switch (operation & 0xF) {
                0x0 => this.ld_vx_vy(),
                0x1 => this.or_vx_vy(),
                0x2 => this.and_vx_vy(),
                0x3 => this.xor_vx_vy(),
                0x4 => this.add_vx_vy(),
                0x5 => this.sub_vx_vy(),
                0x6 => this.shr_vx(),
                0x7 => this.subn_vx_vy(),
                0xE => this.shl_vx(),
                else => this.program_counter += 2,
            }
        },
        0x9000...0x9FFF => this.sne_vx_vy(),
        0xA000...0xAFFF => this.ld_i_addr(),
        0xB000...0xBFFF => this.jp_v0_addr(),
        0xC000...0xCFFF => this.rnd_vx_byte(),
        0xD000...0xDFFF => this.drw_vx_vy_nibble(),
        0xE000...0xEFFF => {
            switch (operation & 0xFF) {
                0x9E => this.skp_vx(),
                0xA1 => this.sknp_vx(),
                else => this.program_counter += 2,
            }
        },
        0xF000...0xFFFF => {
            switch (operation & 0xFF) {
                0x07 => this.ld_vx_dt(),
                0x0A => this.ld_vx_k(),
                0x15 => this.ld_dt_vx(),
                0x18 => this.ld_st_vx(),
                0x1E => this.add_i_vx(),
                0x29 => this.ld_f_vx(),
                0x33 => this.ld_b_vx(),
                0x55 => this.ld_i_vx(),
                0x65 => this.ld_vx_i(),
                else => this.program_counter += 2,
            }
        },
    }
}

fn cls(this: *This) void {
    this.setDrawNeeded();
    for (&this.display) |*row| {
        row.* = 0;
    }

    this.program_counter += 2;
}

fn ret(this: *This) void {
    this.stack_pointer -= 1;
    this.program_counter = this.stack[this.stack_pointer];

    this.program_counter += 2;
}

fn jp_addr(this: *This) void {
    this.program_counter = this.opcode() & 0xFFF;
}

fn call_addr(this: *This) void {
    this.stack[this.stack_pointer] = this.program_counter;
    this.stack_pointer += 1;

    this.program_counter = this.opcode() & 0x0FFF;
}

fn se_vx_byte(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;

    this.program_counter += if (this.registers[x] == (operation & 0xFF)) 4 else 2;
}

fn sne_vx_byte(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;

    this.program_counter += if (this.registers[x] != (operation & 0xFF)) 4 else 2;
}

fn se_vx_vy(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    this.program_counter += if (this.registers[x] == this.registers[y]) 4 else 2;
}

fn ld_vx_byte(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;

    this.registers[x] = @truncate(operation & 0xFF);

    this.program_counter += 2;
}

fn add_vx_byte(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;

    this.registers[x] = @addWithOverflow(this.registers[x], @as(u8, @truncate(operation & 0xFF)))[0];

    this.program_counter += 2;
}

fn ld_vx_vy(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    this.registers[x] = this.registers[y];

    this.program_counter += 2;
}

fn or_vx_vy(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    this.registers[x] |= this.registers[y];
    this.registers[0xF] = 0;

    this.program_counter += 2;
}

fn and_vx_vy(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    this.registers[x] &= this.registers[y];
    this.registers[0xF] = 0;

    this.program_counter += 2;
}

fn xor_vx_vy(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    this.registers[x] ^= this.registers[y];
    this.registers[0xF] = 0;

    this.program_counter += 2;
}

fn add_vx_vy(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    const res = @addWithOverflow(this.registers[x], this.registers[y]);

    this.registers[x] = res[0];
    this.registers[0xF] = res[1];

    this.program_counter += 2;
}

fn sub_vx_vy(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    const sub_res = @subWithOverflow(this.registers[x], this.registers[y]);

    this.registers[x] = sub_res[0];
    this.registers[0xF] = ~sub_res[1];

    this.program_counter += 2;
}

fn shr_vx(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    const flag = this.registers[y] & 1;

    this.registers[x] = this.registers[y] >> 1;
    this.registers[0xF] = flag;

    this.program_counter += 2;
}

fn subn_vx_vy(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    const sub_res = @subWithOverflow(this.registers[y], this.registers[x]);

    this.registers[x] = sub_res[0];
    this.registers[0xF] = ~sub_res[1];

    this.program_counter += 2;
}

fn shl_vx(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    const res = @shlWithOverflow(this.registers[y], 1);

    this.registers[x] = res[0];
    this.registers[0xF] = res[1];

    this.program_counter += 2;
}

fn sne_vx_vy(this: *This) void {
    const operation = this.opcode();
    const x = (operation >> 8) & 0xF;
    const y = (operation >> 4) & 0xF;

    this.program_counter += if (this.registers[x] != this.registers[y]) 4 else 2;
}

fn ld_i_addr(this: *This) void {
    this.index = this.opcode() & 0xFFF;

    this.program_counter += 2;
}

fn jp_v0_addr(this: *This) void {
    this.program_counter = (this.opcode() & 0xFFF) + this.registers[0];
}

fn rnd_vx_byte(this: *This) void {
    const operation = this.opcode();

    const x = (operation >> 8) & 0xF;
    this.registers[x] = this.generator.random().int(u8) & @as(u8, @truncate(operation & 0xFF));

    this.program_counter += 2;
}

fn drw_vx_vy_nibble(this: *This) void {
    this.setDrawNeeded();

    const operation = this.opcode();

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
}

fn skp_vx(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;
    const shift = (@bitSizeOf(@TypeOf(this.keys)) - 1) - @as(u4, @intCast(this.registers[x]));
    const key = ((this.keys >> shift) & 1) == 1;

    this.program_counter += if (key) 4 else 2;
}

fn sknp_vx(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;
    const shift = (@bitSizeOf(@TypeOf(this.keys)) - 1) - @as(u4, @intCast(this.registers[x]));
    const key = ((this.keys >> shift) & 1) == 1;

    this.program_counter += if (!key) 4 else 2;
}

fn ld_vx_dt(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;
    this.registers[x] = this.delay_timer;

    this.program_counter += 2;
}

fn ld_vx_k(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;

    const keys_statuses = this.keysStatuses();

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

            this.program_counter += 2;
        } else {
            keys_statuses[1] = this.keys;
        }
    }
}

fn ld_dt_vx(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;

    this.delay_timer = this.registers[x];

    this.program_counter += 2;
}

fn ld_st_vx(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;

    this.sound_timer = this.registers[x];

    this.program_counter += 2;
}

fn add_i_vx(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;

    this.index += this.registers[x];

    this.program_counter += 2;
}

fn ld_f_vx(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;

    this.index = x * 5;

    this.program_counter += 2;
}

fn ld_b_vx(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;

    this.ram[this.index] = @divTrunc(this.registers[x], 100);
    this.ram[this.index + 1] = @divTrunc(this.registers[x], 10) % 10;
    this.ram[this.index + 2] = this.registers[x] % 10;

    this.program_counter += 2;
}

fn ld_i_vx(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;

    std.mem.copyForwards(u8, this.ram[this.index..], this.registers[0 .. x + 1]);
    this.index += 1;

    this.program_counter += 2;
}

fn ld_vx_i(this: *This) void {
    const x = (this.opcode() >> 8) & 0xF;

    std.mem.copyForwards(u8, &this.registers, this.ram[this.index .. this.index + x + 1]);
    this.index += 1;

    this.program_counter += 2;
}

fn opcode(this: This) u16 {
    return @as(u16, this.ram[this.program_counter]) << 8 | this.ram[this.program_counter + 1];
}

fn keysStatuses(this: *This) *[2]u16 {
    const keys_statuses_location = font.len;
    return @ptrCast(@alignCast(&this.ram[keys_statuses_location]));
}

fn drawNeeded(this: *This) *u8 {
    const draw_needed_location = font.len + 4;
    return &this.ram[draw_needed_location];
}

fn setDrawNeeded(this: *This) void {
    this.drawNeeded().* = 1;
}

pub fn isDrawNeeded(this: *This) bool {
    return this.drawNeeded().* == 1;
}

pub fn clearDrawNeeded(this: *This) void {
    this.drawNeeded().* = 0;
}

test "Corax+ opcode" {
    const rom = try std.fs.cwd().openFile("3-corax+.ch8", .{});
    var chip = try init(rom.reader().any(), 0);
    rom.close();

    // 1116 is the last instruction location for corax+ rom
    while (chip.program_counter != 1116) {
        chip.cycle();
    }

    // Screen dump when every instruction passes checks.
    const expected_display = [_]@TypeOf(chip.display[0]){ 0, 0, 981482112, 981482368, 420743444, 999564052, 177746584, 681062552, 982530704, 948970256, 0, 0, 713046912, 998259584, 957623060, 991175060, 177744408, 681062552, 177224592, 990913424, 0, 0, 981482368, 998259584, 823409300, 949232404, 177744536, 689451544, 848313232, 957358992, 0, 0, 981482240, 964690560, 152320276, 974399764, 311961880, 731392664, 311442320, 999297680, 0, 0, 981482368, 998244352, 957626516, 991166464, 177744664, 706215936, 848313232, 999292928, 0, 0, 847264640, 964690564, 286538132, 571747212, 311961752, 865609860, 982530960, 596644014, 0, 0, 0, 0 };

    if (std.testing.expectEqualDeep(expected_display, chip.display)) |_| {} else |_| {
        std.debug.print(
            \\ The display output doesn't match the expected value.
            \\ If the draw instruction (0xDxyn) is correctly working, one or more instructions are wrongly implemented
            \\ Run the 3-corax+.ch8 rom with display output to know which one is failing
        , .{});
    }
}

test "Flags" {
    const rom = try std.fs.cwd().openFile("4-flags.ch8", .{});
    var chip = try init(rom.reader().any(), 0);
    rom.close();

    while (chip.program_counter != 1346) {
        chip.cycle();
    }

    const expected_display = [_]@TypeOf(chip.display[0]){ 2764874496, 917504, 3937050901, 1409439056, 2932621593, 2550949472, 2861056913, 269370432, 0, 0, 3758097024, 917504, 1700070293, 1431065941, 644219033, 2575459942, 3829661841, 286016580, 0, 0, 3758097280, 917504, 2236940437, 1431065936, 3865444505, 2575853152, 3829661841, 286147648, 0, 0, 0, 0, 3838616192, 917504, 2326438805, 1431065941, 2395750553, 2575459942, 3937026193, 286016580, 0, 0, 3758097280, 917504, 2236940437, 1431065936, 3865444505, 2575853152, 3829661841, 286147648, 0, 0, 0, 0, 4004430776, 644, 2766971441, 1409297292, 2762523425, 2550147204, 3836650041, 268439726, 0, 0 };

    if (std.testing.expectEqualDeep(expected_display, chip.display)) |_| {} else |_| {
        std.debug.print(
            \\ The display output doesn't match the expected value.
            \\ If the draw instruction (0xDxyn) is correctly working, one or more instructions are wrongly implemented
            \\ Run the 4-flags.ch8 rom with display output to know which one is failing
        , .{});
    }
}
