const Zip = @This();

const std = @import("std");

const c = @cImport(@cInclude("zip/zip.h"));

ptr: *c.zip_t,

pub const Error = error{
    InvalidEntryName,
    EntryNotFound,
    InvalidMode,
    InvalidCompressionLevel,
    CannotOpenFile,
    EntryIsDir,
    CannotExtractData,
    OutOfMemory,
};

fn makeError(err: c_int) Error {
    return switch (err) {
        c.ZIP_EINVENTNAME => error.InvalidEntryName,
        c.ZIP_ENOENT => error.EntryNotFound,
        c.ZIP_EINVMODE => error.InvalidMode,
        c.ZIP_EINVLVL => error.InvalidCompressionLevel,
        c.ZIP_EOPNFILE => error.CannotOpenFile,
        c.ZIP_EINVENTTYPE => error.EntryIsDir,
        c.ZIP_EMEMNOALLOC => error.CannotExtractData,
        c.ZIP_EOOMEM => error.OutOfMemory,
        // remaining codes appear to not be reachable by the functions used
        else => unreachable,
    };
}

pub fn read(path: []const u8) !Zip {
    const str = try std.os.toPosixPath(path);
    // could be a memory error, but we can't tell the difference
    const ptr = c.zip_open(&str, 0, 'r') orelse return error.FileNotFound;
    return Zip{ .ptr = ptr };
}

pub inline fn close(self: Zip) void {
    c.zip_close(self.ptr);
}

pub fn openEntry(self: Zip, file: []const u8) !void {
    const str = try std.os.toPosixPath(file);
    const err = c.zip_entry_open(self.ptr, &str);
    if (err < 0) return makeError(err);
}

pub inline fn closeEntry(self: Zip) void {
    _ = c.zip_entry_close(self.ptr);
}

pub inline fn entrySize(self: Zip) u64 {
    return c.zip_entry_size(self.ptr);
}

pub fn readEntry(self: Zip, buf: []u8) !void {
    const err = c.zip_entry_noallocread(self.ptr, buf.ptr, buf.len);
    if (err < 0) return makeError(@intCast(c_int, err));
}
