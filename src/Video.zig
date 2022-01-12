const Video = @This();

const SDL = @import("sdl2");
const std = @import("std");

const ROM = @import("ROM.zig");

const Sprite = struct {
    id: u6 = 0,
    x_flip: bool = false,
    y_flip: bool = false,
    color: u8 = 0,
    x_pos: u8 = 0,
    y_pos: u8 = 0,

    pub fn readAttrs(self: Sprite) u8 {
        return (@as(u8, self.id) << 2) |
            (@as(u8, @boolToInt(self.x_flip)) << 1) |
            @boolToInt(self.y_flip);
    }

    pub fn writeAttrs(self: *Sprite, attrs: u8) void {
        self.y_flip = (attrs & 1) != 0;
        self.x_flip = (attrs & 2) != 0;
        self.id = @intCast(u6, attrs >> 2);
    }
};

const SCREEN_WIDTH = 224;
const SCREEN_HEIGHT = 288;

const BGTiles = [256][8][8]u2;
const FGTiles = [64][16][16]u2;
const VideoRAM = [0x400]u8;

/// game window
window: SDL.Window,
/// game renderer
renderer: SDL.Renderer,
/// graphics drawn here
canvas: SDL.Texture,

// rom data
bg_tiles: *BGTiles,
fg_tiles: *FGTiles,
palettes: *[32][4]SDL.Color,

// runtime data
vram: *VideoRAM,
cram: *VideoRAM,
sprites: [8]Sprite = [_]Sprite{.{}} ** 8,
flip: bool = false,

const TEXTURE_FORMAT = switch (@import("builtin").cpu.arch.endian()) {
    .Big => .rgba8888,
    .Little => .abgr8888,
};

fn decodePixel(b: u8) u2 {
    return @truncate(u2, (b & 1) | ((b >> 3) & 2));
}

fn decodeGfxBlock(comptime span: u8, out: *[span][span]u2, in: [*]const u8) [*]const u8 {
    const z_loop_count = span / 4;
    const y_out_mask = span - 1;
    const ptr_jump = (span * 2) - 8;

    var xout = span;
    var ptr = in;
    while (xout > 0) {
        xout -= 1;
        var y: u3 = 0;
        while (y < 4) : (y += 1) {
            var z: usize = 0;
            var yout = y_out_mask - y;
            while (z < z_loop_count) : (z += 1) {
                out[yout][xout] = decodePixel(ptr[z * 8] >> y);
                yout = (yout + 4) & y_out_mask;
            }
        }
        ptr += 1;
        if ((xout & 7) == 0) {
            ptr += ptr_jump;
        }
    }
    return ptr;
}

fn scale8(value: u8) u8 {
    return (value * 36) + (value >> 2);
}

pub fn init(allocator: std.mem.Allocator, rom: *const ROM) !Video {
    const window = try SDL.createWindow(
        "PAC-MAN",
        .centered,
        .centered,
        SCREEN_WIDTH * 2,
        SCREEN_HEIGHT * 2,
        .{ .resizable = true },
    );
    errdefer window.destroy();

    const renderer = try SDL.createRenderer(window, 0, .{});
    errdefer renderer.destroy();

    const canvas = try SDL.createTexture(
        renderer,
        TEXTURE_FORMAT,
        .streaming,
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
    );
    errdefer canvas.destroy();

    const bg_tiles = try allocator.create(BGTiles);
    errdefer allocator.destroy(bg_tiles);
    const fg_tiles = try allocator.create(FGTiles);
    errdefer allocator.destroy(fg_tiles);

    var ptr = @as([*]const u8, &rom.bg_tiles);
    for (bg_tiles) |*tile| {
        ptr = decodeGfxBlock(8, tile, ptr);
    }

    ptr = @as([*]const u8, &rom.fg_tiles);
    for (fg_tiles) |*tile| {
        ptr = decodeGfxBlock(16, tile, ptr);
    }

    var colors: [32]SDL.Color = undefined;
    for (rom.colors) |color, i| {
        colors[i] = .{
            .r = scale8(color & 7),
            .g = scale8((color >> 3) & 7),
            .b = (color >> 6) * 85,
            .a = 255,
        };
    }
    colors[0].a = 0;

    const palettes = try allocator.create([32][4]SDL.Color);
    errdefer allocator.destroy(palettes);

    var i: u16 = 0;
    for (palettes) |*pal| {
        for (pal) |*color| {
            color.* = colors[rom.palettes[i]];
            i += 1;
        }
    }

    const vram = try allocator.create(VideoRAM);
    errdefer allocator.destroy(vram);

    std.mem.set(u8, vram, 0);

    const cram = try allocator.create(VideoRAM);
    errdefer allocator.destroy(cram);

    std.mem.set(u8, cram, 0);

    return Video{
        .window = window,
        .renderer = renderer,
        .canvas = canvas,

        .bg_tiles = bg_tiles,
        .fg_tiles = fg_tiles,
        .palettes = palettes,

        .vram = vram,
        .cram = cram,
    };
}

pub fn deinit(self: Video, allocator: std.mem.Allocator) void {
    allocator.destroy(self.bg_tiles);
    allocator.destroy(self.fg_tiles);
    allocator.destroy(self.palettes);

    allocator.destroy(self.vram);
    allocator.destroy(self.cram);

    self.canvas.destroy();
    self.renderer.destroy();
    self.window.destroy();
}

fn plotPixel(pixels: SDL.Texture.PixelData, x: usize, y: usize, color: SDL.Color) void {
    @ptrCast([*]align(1) SDL.Color, &pixels.pixels[y * pixels.stride])[x] = color;
}

fn drawChar(self: Video, pixels: SDL.Texture.PixelData, x: usize, y: usize, address: usize) void {
    var addr = address;
    var mask: u8 = 0;
    if (self.flip) {
        addr ^= 0x3ff;
        mask = 7;
    }
    const palette = self.palettes[self.cram[addr] & 31];
    for (self.bg_tiles[self.vram[addr]]) |row, py| {
        for (row) |pixel, px| {
            plotPixel(pixels, x + (px ^ mask), y + (py ^ mask), palette[pixel]);
        }
    }
}

fn drawBackground(self: Video, pixels: SDL.Texture.PixelData) void {
    var x: usize = 0;
    while (x < SCREEN_WIDTH / 8) : (x += 1) {
        self.drawChar(pixels, x << 3, 0x00 << 3, 0x3dd - x);
        self.drawChar(pixels, x << 3, 0x01 << 3, 0x3fd - x);
        self.drawChar(pixels, x << 3, 0x22 << 3, 0x01d - x);
        self.drawChar(pixels, x << 3, 0x23 << 3, 0x03d - x);
    }
    var y: usize = 2;
    while (y < SCREEN_HEIGHT / 8 - 2) : (y += 1) {
        x = 0;
        while (x < SCREEN_WIDTH / 8) : (x += 1) {
            self.drawChar(pixels, x << 3, y << 3, 0x39e + y - (x << 5));
        }
    }
}

fn drawSprite(self: Video, pixels: SDL.Texture.PixelData, index: u8) void {
    const sprite = self.sprites[index];
    const x = -%sprite.x_pos -% 17 -% @boolToInt(index < 3);
    const y = -%sprite.y_pos +% 16;
    const xm: u8 = if (sprite.x_flip) 0x0f else 0x00;
    const ym: u8 = if (sprite.y_flip) 0x0f else 0x00;
    const palette = self.palettes[sprite.color & 31];

    for (self.fg_tiles[sprite.id]) |row, py| {
        const sy = @as(u16, y +% (@intCast(u8, py) ^ ym) -% 16) + 16;
        for (row) |pixel, px| {
            const sx = x +% (@intCast(u8, px) ^ xm);
            if (sx >= SCREEN_WIDTH) continue;
            const color = palette[pixel];
            if (color.a == 0) continue;
            plotPixel(pixels, sx, sy, color);
        }
    }
}

fn drawScreen(self: Video, pixels: SDL.Texture.PixelData) void {
    self.drawBackground(pixels);
    var i: u8 = 6;
    while (i >= 1) : (i -= 1) {
        self.drawSprite(pixels, i);
    }
}

pub fn update(self: Video) !void {
    var pixels = try self.canvas.lock(null);
    defer pixels.release();
    self.drawScreen(pixels);
}

pub fn present(self: Video) !void {
    try self.renderer.copy(self.canvas, null, null);
    self.renderer.present();
}
