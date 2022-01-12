const Timer = @This();

const SDL = @import("sdl2");

/// SDL ticks at last frame
target: u32,
/// 60hz helper
divider: u2 = 0,

pub fn init() Timer {
    return .{ .target = @intCast(u32, SDL.getTicks()) };
}

pub fn tick(self: *Timer) void {
    // add 17 ms to target
    self.target += 17;
    if (self.divider == 2) {
        // one out of every three frames is 16 ms instead of 17, to best approximate 60 fps
        self.target -= 1;
        self.divider = 0;
    } else {
        self.divider += 1;
    }
    // wait until target reached
    const now = @intCast(u32, SDL.getTicks());
    if (now < self.target) {
        SDL.delay(self.target - now);
    }
}
