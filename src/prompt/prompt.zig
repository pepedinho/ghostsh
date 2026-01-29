const std = @import("std");
const parser = @import("../parsing/parsing.zig");
const rl = @import("../readline.zig");

pub fn receivePrompt(allocator: std.mem.Allocator) !void {
    while (true) {
        const command_line = rl.readline(allocator, "gsh> ") orelse {
            std.debug.print("error", .{});
            return;
        };
        defer rl.free(command_line);
        parser.parse(allocator, command_line) catch |err| {
            switch (err) {
                inline else => std.debug.print("gsh: error: {s}\n", .{@errorName(err)}),
            }
            continue;
        };
        std.debug.print("{s}\n", .{command_line});
    }
}
