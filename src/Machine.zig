const SDL = @import("sdl2");
const std = @import("std");
const z80 = @import("zig80");

const Audio = @import("Audio.zig");
const Inputs = @import("Inputs.zig");
const ROM = @import("ROM.zig");
const Timer = @import("Timer.zig");
const Video = @import("Video.zig");

const Machine = @This();

const CYCLES_PER_FRAME = 51200;

code: *[0x4000]u8,

wram: *[0x3f0]u8,

video: Video,
audio: Audio,
inputs: Inputs = .{},
watchdog: u8 = 0,

interrupt_vector: u8 = 0,
interrupt_enable: bool = false,

dips: u8 = 0,

pub fn init(allocator: std.mem.Allocator, rom_folder: []const u8) !Machine {
    const rom = try ROM.init(allocator, rom_folder);
    defer rom.deinit(allocator);

    const video = try Video.init(allocator, rom);
    errdefer video.deinit(allocator);

    const audio = try Audio.init(allocator, rom);
    errdefer audio.deinit(allocator);

    const code = try allocator.create([0x4000]u8);
    errdefer allocator.destroy(code);
    code.* = rom.code;

    const wram = try allocator.create([0x3f0]u8);
    errdefer allocator.destroy(wram);

    std.mem.set(u8, wram, 0);

    return Machine{
        .code = code,

        .wram = wram,

        .video = video,
        .audio = audio,
    };
}

pub fn deinit(self: Machine, allocator: std.mem.Allocator) void {
    allocator.destroy(self.code);
    allocator.destroy(self.wram);
    self.video.deinit(allocator);
    self.audio.deinit(allocator);
}

fn read(self: *Machine, address: u16) u8 {
    const addr = address & 0x7fff;
    return switch (addr) {
        0x0000...0x3fff => self.code[addr],
        0x4000...0x43ff => self.video.vram[addr - 0x4000],
        0x4400...0x47ff => self.video.cram[addr - 0x4400],
        0x4c00...0x4fef => self.wram[addr - 0x4c00],
        0x4ff0...0x4fff => {
            const sprite = self.video.sprites[(addr & 0xf) >> 1];
            return switch (@truncate(u1, addr)) {
                0 => sprite.readAttrs(),
                1 => sprite.color,
            };
        },
        0x5000 => self.inputs.in0,
        0x5040 => self.inputs.in1,
        0x5080 => self.dips,
        else => 0,
    };
}

fn write(self: *Machine, address: u16, value: u8) void {
    const addr = address & 0x7fff;
    switch (addr) {
        0x4000...0x43ff => self.video.vram[addr - 0x4000] = value,
        0x4400...0x47ff => self.video.cram[addr - 0x4400] = value,
        0x4c00...0x4fef => self.wram[addr - 0x4c00] = value,
        0x4ff0...0x4fff => {
            const sprite = &self.video.sprites[(addr & 0xf) >> 1];
            switch (@truncate(u1, addr)) {
                0 => sprite.writeAttrs(value),
                1 => sprite.color = value,
            }
        },
        0x5000 => self.interrupt_enable = value != 0,
        0x5001 => self.audio.enabled = value != 0,
        0x5003 => self.video.flip = value != 0,
        0x5040 => self.audio.voices[0].setAccNybble(0, @truncate(u4, value)),
        0x5041...0x504f => {
            const voice = &self.audio.voices[(addr - 0x5041) / 5];
            switch ((addr - 0x5041) % 5) {
                0...3 => |i| voice.setAccNybble(@intCast(u3, i) + 1, @truncate(u4, value)),
                4 => voice.wave = @truncate(u4, value),
                else => unreachable,
            }
        },
        0x5050 => self.audio.voices[0].setFreqNybble(0, @truncate(u4, value)),
        0x5051...0x505f => {
            const voice = &self.audio.voices[(addr - 0x5051) / 5];
            switch ((addr - 0x5051) % 5) {
                0...3 => |i| voice.setFreqNybble(@intCast(u3, i) + 1, @truncate(u4, value)),
                4 => voice.vol = @truncate(u4, value),
                else => unreachable,
            }
        },
        0x5060...0x506f => {
            const sprite = &self.video.sprites[(addr & 0xf) >> 1];
            switch (@truncate(u1, addr)) {
                0 => sprite.x_pos = value,
                1 => sprite.y_pos = value,
            }
        },
        0x50c0 => self.watchdog = 0,
        else => {},
    }
}

fn irq(self: *Machine) u8 {
    return self.interrupt_vector;
}

fn out(self: *Machine, port: u16, value: u8) void {
    _ = port;
    self.interrupt_vector = value;
}

pub fn run(self: *Machine) !void {
    // interface for CPU
    const interface = z80.Interface.init(self, .{
        .read = read,
        .write = write,
        .irq = irq,
        .out = out,
    });
    // CPU to run game
    var cpu = z80.CPU{ .interface = interface };
    // 60hz timer
    var timer = Timer.init();
    // we're waiting for the CPU to be ready to accept an interrupt
    var irq_pending = false;
    while (true) {
        if (!self.inputs.pause) {
            // step cpu until vblank
            while (cpu.cycles < CYCLES_PER_FRAME) {
                if (irq_pending and cpu.irq()) {
                    irq_pending = false;
                }
                cpu.step();
            }
            cpu.cycles -= CYCLES_PER_FRAME;
            // check watchdog
            self.watchdog += 1;
            if (self.watchdog == 16) return error.Watchdog;
            // queue irq if enabled
            if (self.interrupt_enable) irq_pending = true;
            // update outputs
            try self.audio.update();
            try self.video.update();
        }
        // check inputs, quit if requested
        while (SDL.pollEvent()) |event| switch (event) {
            .quit => return,
            .key_down => |key| self.inputs.onKeyDown(key.keycode),
            .key_up => |key| self.inputs.onKeyUp(key.keycode),
            else => {},
        };
        // present the display (even if paused, in case the window was resized)
        try self.video.present();
        // wait for next frame
        timer.tick();
    }
}
