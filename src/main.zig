const clap = @import("clap");
const SDL = @import("sdl2");
const std = @import("std");

const Machine = @import("Machine.zig");

const DEFAULT_EXE_ARG = "pacman";

const COINAGE = std.ComptimeStringMap(u8, .{
    .{ "free", 0x00 },
    .{ "1:1", 0x01 },
    .{ "1:2", 0x02 },
    .{ "2:1", 0x03 },
});

const LIVES = std.ComptimeStringMap(u8, .{
    .{ "1", 0x00 },
    .{ "2", 0x04 },
    .{ "3", 0x08 },
    .{ "5", 0x0c },
});

const BONUS = std.ComptimeStringMap(u8, .{
    .{ "10k", 0x00 },
    .{ "15k", 0x10 },
    .{ "20k", 0x20 },
    .{ "none", 0x30 },
});

fn stderr() std.fs.File.Writer {
    return std.io.getStdErr().writer();
}

fn parseParam(comptime str: []const u8) clap.Param(clap.Help) {
    return clap.parseParam(str) catch unreachable;
}

const params = [_]clap.Param(clap.Help){
    parseParam("-h, --help             display help and exit"),
    parseParam("-t, --cocktail         cocktail mode - for tabletop play"),
    parseParam("-c, --coinage <ratio>  coins to credits ratio - free, 1:1, 1:2, or 2:1\ndefault: free"),
    parseParam("-l, --lives <num>      number of lives - 1, 2, 3, or 5\ndefault: 3"),
    parseParam("-b, --bonus <points>   extra life bonus - 10k, 15k, 20k, or none\ndefault: 10k"),
    parseParam("-d, --hard             hard mode"),
    parseParam("-a, --alt-ghost-names  alternate ghost names"),
    parseParam("<rom directory>"),
};

fn printHelp(exe_arg: []const u8) !void {
    try stderr().print("usage: {s} ", .{exe_arg});
    try clap.usage(stderr(), &params);
    try stderr().writeAll("\n");
    try clap.help(stderr(), &params);
    try stderr().writeAll("controls:\n" ++
        "\tarrow keys  move\n" ++
        "\twasd        move (player two, cocktail mode)\n" ++
        "\tc           insert coin\n" ++
        "\t1           start one player game\n" ++
        "\t2           start two player game\n" ++
        "\tp           pause game\n" ++
        "\tf1          toggle rack test\n" ++
        "\tf2          toggle service mode\n");
}

pub fn main() u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, .{ .diagnostic = &diag }) catch |err| {
        var iter = std.process.args();
        defer iter.deinit();

        diag.report(std.io.getStdErr().writer(), err) catch {};

        return 1;
    };
    defer args.deinit();

    if (args.flag("--help")) {
        printHelp(args.exe_arg orelse DEFAULT_EXE_ARG) catch {};
        return 0;
    }

    const positionals = args.positionals();
    if (positionals.len < 1) {
        stderr().writeAll("missing path to roms\n") catch {};
        return 1;
    }

    SDL.init(.{ .video = true, .audio = true, .events = true }) catch return 1;
    defer SDL.quit();

    var machine = Machine.init(allocator, positionals[0]) catch |err| {
        stderr().print("failed to set up machine: {s}\n", .{@errorName(err)}) catch {};
        return 1;
    };
    defer machine.deinit(allocator);

    if (args.flag("--cocktail")) {
        machine.inputs.cocktailMode();
    }

    machine.dips |= COINAGE.get(args.option("--coinage") orelse "free") orelse {
        stderr().writeAll("invalid setting for '--coinage'\n") catch {};
        return 1;
    };

    machine.dips |= LIVES.get(args.option("--lives") orelse "3") orelse {
        stderr().writeAll("invalid setting for --lives\n") catch {};
        return 1;
    };

    machine.dips |= BONUS.get(args.option("--bonus") orelse "10k") orelse {
        stderr().writeAll("invalid setting for --bonus\n") catch {};
        return 1;
    };

    if (!args.flag("--hard")) {
        machine.dips |= 0x40;
    }

    if (!args.flag("--alt-ghost-names")) {
        machine.dips |= 0x80;
    }

    machine.run() catch |err| {
        stderr().print("game crashed: {s}\n", .{@errorName(err)}) catch {};
        return 1;
    };

    return 0;
}
