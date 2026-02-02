const std = @import("std");
const parser = @import("../parsing/parsing.zig");
const rl = @import("../readline.zig");

// Number of bytes of accumulated command input after which we force a full
// arena reset (free_all) to prevent unbounded memory growth.
const ARENA_REINIT_THRESHOLD = 1000;
var arena_size: usize = 0;

pub fn receivePrompt() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
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
            rl.free(command_line);
            clearArena(&arena, command_line);
            continue;
        };
        std.debug.print("{s}\n", .{command_line});

        rl.free(command_line);
        clearArena(&arena, command_line);
    }
}

fn clearArena(arena: *std.heap.ArenaAllocator, command_line: []const u8) void {
    arena_size += command_line.len;
    if (arena_size > ARENA_REINIT_THRESHOLD) {
        _ = arena.reset(.free_all);
    } else {
        _ = arena.reset(.retain_capacity);
    }
}
