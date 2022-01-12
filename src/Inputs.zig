const Inputs = @This();

const SDL = @import("sdl2");

const ButtonEntry = struct { keycode: SDL.Keycode, port: u1, bitmask: u8 };

const BUTTON_MAP = [_]ButtonEntry{
    .{ .keycode = .up, .port = 0, .bitmask = UP },
    .{ .keycode = .left, .port = 0, .bitmask = LEFT },
    .{ .keycode = .right, .port = 0, .bitmask = RIGHT },
    .{ .keycode = .down, .port = 0, .bitmask = DOWN },
    .{ .keycode = .c, .port = 0, .bitmask = COIN_1 },
    .{ .keycode = .w, .port = 1, .bitmask = UP },
    .{ .keycode = .a, .port = 1, .bitmask = LEFT },
    .{ .keycode = .d, .port = 1, .bitmask = RIGHT },
    .{ .keycode = .s, .port = 1, .bitmask = DOWN },
    .{ .keycode = .@"1", .port = 1, .bitmask = START_1 },
    .{ .keycode = .@"2", .port = 1, .bitmask = START_2 },
};

fn getButtonMapping(keycode: SDL.Keycode) ?*const ButtonEntry {
    for (BUTTON_MAP) |*entry| {
        if (entry.keycode == keycode) return entry;
    }
    return null;
}

const UP: u8 = 1 << 0;
const LEFT: u8 = 1 << 1;
const RIGHT: u8 = 1 << 2;
const DOWN: u8 = 1 << 3;

const RACK_TEST: u8 = 1 << 4;
const COIN_1: u8 = 1 << 5;
const COIN_2: u8 = 1 << 6;
const COIN_3: u8 = 1 << 7;

const SERVICE: u8 = 1 << 4;
const START_1: u8 = 1 << 5;
const START_2: u8 = 1 << 6;
const CABINET: u8 = 1 << 7;

in0: u8 = 0xff,
in1: u8 = 0xff,

pause: bool = false,

pub fn cocktailMode(self: *Inputs) void {
    self.in1 &= ~CABINET;
}

pub fn onKeyDown(self: *Inputs, keycode: SDL.Keycode) void {
    switch (keycode) {
        .f1 => self.in0 ^= RACK_TEST,
        .f2 => self.in1 ^= SERVICE,
        .p => self.pause = !self.pause,
        else => if (getButtonMapping(keycode)) |entry| {
            switch (entry.port) {
                0 => self.in0 &= ~entry.bitmask,
                1 => self.in1 &= ~entry.bitmask,
            }
        },
    }
}

pub fn onKeyUp(self: *Inputs, keycode: SDL.Keycode) void {
    if (getButtonMapping(keycode)) |entry| {
        switch (entry.port) {
            0 => self.in0 |= entry.bitmask,
            1 => self.in1 |= entry.bitmask,
        }
    }
}
