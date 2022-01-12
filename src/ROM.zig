const ROM = @This();

const SDL = @import("sdl2");
const std = @import("std");

const Zip = @import("Zip.zig");

code: [0x4000]u8,
bg_tiles: [0x1000]u8,
fg_tiles: [0x1000]u8,
palettes: [0x100]u8,
waves: [0x100]u8,
colors: [0x20]u8,

pub fn init(allocator: std.mem.Allocator, rom_folder: []const u8) !*ROM {
    const self = try allocator.create(ROM);
    errdefer allocator.destroy(self);

    try self.readPacData(allocator, rom_folder);
    try self.readPuckData(allocator, rom_folder);

    return self;
}

pub fn deinit(self: *ROM, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

fn readZipFile(zip: Zip, file: []const u8, buf: []u8) !void {
    try zip.openEntry(file);
    defer zip.closeEntry();

    if (zip.entrySize() != buf.len) return error.InvalidFileSize;
    try zip.readEntry(buf);
}

fn readPacData(self: *ROM, allocator: std.mem.Allocator, rom_folder: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ rom_folder, "pacman.zip" });
    defer allocator.free(path);

    const zip = try Zip.read(path);
    defer zip.close();

    try readZipFile(zip, "pacman.5e", &self.bg_tiles);
    try readZipFile(zip, "pacman.5f", &self.fg_tiles);
    try readZipFile(zip, "pacman.6e", self.code[0x0000..0x1000]);
    try readZipFile(zip, "pacman.6f", self.code[0x1000..0x2000]);
    try readZipFile(zip, "pacman.6h", self.code[0x2000..0x3000]);
    try readZipFile(zip, "pacman.6j", self.code[0x3000..0x4000]);
}

fn readPuckData(self: *ROM, allocator: std.mem.Allocator, rom_folder: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ rom_folder, "puckman.zip" });
    defer allocator.free(path);

    const zip = try Zip.read(path);
    defer zip.close();

    try readZipFile(zip, "pm1-1.7f", &self.colors);
    try readZipFile(zip, "pm1-4.4a", &self.palettes);
    try readZipFile(zip, "pm1-3.1m", &self.waves);
}
