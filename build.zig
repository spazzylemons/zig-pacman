const deps = @import("deps.zig");
const Sdk = @import("SDL.zig/Sdk.zig");
const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zig-pacman", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    deps.addAllTo(exe);
    // SDL2
    const sdk = Sdk.init(b);
    sdk.link(exe, .dynamic);
    exe.addPackage(sdk.getWrapperPackage("sdl2"));
    // kuba-- zip
    exe.linkLibC();
    exe.addIncludeDir("src");
    exe.addCSourceFile("src/zip/zip.c", &.{"-fno-sanitize=undefined"});
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
