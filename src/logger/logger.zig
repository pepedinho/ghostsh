const std = @import("std");

pub var is_on = false;

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (is_on) {
        std.debug.print(fmt, args);
    }
}
