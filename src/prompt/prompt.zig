const std = @import("std");
const parser = @import("../parsing/parsing.zig");
const rl = @import("../readline.zig");

pub fn receivePrompt() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    while (true) {
        const allocator = arena.allocator();

        const command_line = rl.readline(allocator, "gsh> ") orelse {
            std.debug.print("error", .{});
            return;
        };
        parser.parse(allocator, command_line) catch |err| {
            switch (err) {
                inline else => std.debug.print("gsh: error: {s}\n", .{@errorName(err)}),
            }
            continue;
        };
        std.debug.print("{s}\n", .{command_line});
        if (command_line.len > 1000) {
            arena.deinit();
            arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        } else {
            _ = arena.reset(.retain_capacity);
        }
        rl.free(command_line);
    }
}
