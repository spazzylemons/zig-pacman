const Audio = @This();

const SDL = @import("sdl2");
const std = @import("std");

const ROM = @import("ROM.zig");

const SAMPLE_RATE = 48000;
const SAMPLE_CHUNK_SIZE = SAMPLE_RATE / 60;
const AMP_FACTOR = 64; // arbitrary value so sound isn't so quiet

const Wave = [32]u8;

fn setVoiceNybble(value: u20, index: u3, nybble_value: u4) u20 {
    const shift = @as(u5, index) << 2;
    return value & ~(@as(u20, 0xf) << shift) | (@as(u20, nybble_value) << shift);
}

const Voice = struct {
    acc: u20 = 0,
    wave: u4 = 0,
    freq: u20 = 0,
    vol: u4 = 0,

    pub fn setAccNybble(self: *Voice, index: u3, value: u4) void {
        self.acc = setVoiceNybble(self.acc, index, value);
    }

    pub fn setFreqNybble(self: *Voice, index: u3, value: u4) void {
        self.freq = setVoiceNybble(self.freq, index, value);
    }
};

device: SDL.AudioDevice,
enabled: bool,
voices: [3]Voice,
waves: *[8]Wave,

pub fn init(allocator: std.mem.Allocator, rom: *const ROM) !Audio {
    const device = (try SDL.openAudioDevice(.{ .desired_spec = .{
        .sample_rate = SAMPLE_RATE,
        .buffer_format = SDL.AudioFormat.s16_sys,
        .channel_count = 1,
        .buffer_size_in_frames = SAMPLE_CHUNK_SIZE,
        .callback = null,
        .userdata = null,
    } })).device;
    errdefer device.close();

    device.pause(false);

    const waves = try allocator.create([8]Wave);
    errdefer allocator.destroy(waves);

    waves.* = @bitCast([8]Wave, rom.waves);

    return Audio{
        .device = device,
        .enabled = false,
        .voices = [_]Voice{.{}} ** 3,
        .waves = waves,
    };
}

pub fn deinit(self: Audio, allocator: std.mem.Allocator) void {
    allocator.destroy(self.waves);
    self.device.close();
}

pub fn update(self: *Audio) !void {
    var buf = std.mem.zeroes([SAMPLE_CHUNK_SIZE]u16);
    if (self.enabled) {
        for (self.voices) |*voice| {
            if (voice.vol == 0) continue;
            for (buf) |*b| {
                voice.acc +%= voice.freq *% 2;
                b.* += @as(u16, AMP_FACTOR) * voice.vol * self.waves[voice.wave][voice.acc >> 15];
            }
        }
    }
    if (SDL.c.SDL_QueueAudio(self.device.id, &buf, SAMPLE_CHUNK_SIZE * @sizeOf(u16)) != 0) {
        return SDL.makeError();
    }
}
