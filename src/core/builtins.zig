const std = @import("std");
const logger = @import("../logger/logger.zig");

pub fn cd(argv: []const []const u8) u8 {
    logger.debug("argv {any}", .{argv});

    if (argv.len == 0) {
        std.posix.chdir("/home") catch |err| {
            std.debug.print("gsh: {s}\n", .{@errorName(err)});
            return 1;
        };

        return 0;
    }

    std.posix.chdir(argv[0]) catch |err| {
        std.debug.print("gsh: {s}", .{@errorName(err)});
        return 1;
    };
    return 0;
}
