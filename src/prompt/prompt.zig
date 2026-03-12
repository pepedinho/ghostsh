const std = @import("std");
const parser = @import("../parsing/parsing.zig");
const rl = @import("../readline.zig");

// Number of bytes of accumulated command input after which we force a full
// arena reset (free_all) to prevent unbounded memory growth.
const ARENA_REINIT_THRESHOLD = 1000;
var arena_size: usize = 0;
pub var sigint_received = std.atomic.Value(bool).init(false);

pub fn receivePrompt(env: *const std.process.EnvMap) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    initReadline();
    while (true) {
        const allocator = arena.allocator();

        const command_line = rl.readline(allocator, "gsh> ") orelse {
            if (sigint_received.load(.monotonic)) {
                _ = sigint_received.swap(false, .monotonic);
                continue;
            }
            std.debug.print("exit", .{});
            return;
        };

        if (sigint_received.swap(false, .monotonic)) {
            rl.free(command_line);
            continue;
        }

        parser.parse(allocator, command_line, env) catch |err| {
            switch (err) {
                inline else => std.debug.print("gsh: error: {s}\n", .{@errorName(err)}),
            }
            rl.free(command_line);
            clearArena(&arena, command_line);
            continue;
        };

        rl.free(command_line);
        clearArena(&arena, command_line);
    }
}

pub fn sigEvent() callconv(.c) c_int {
    if (sigint_received.load(.monotonic)) {
        rl.c.rl_done = 1;
    }
    return 0;
}

pub fn rlDone() void {
    rl.c.rl_done = 1;
}

pub fn initReadline() void {
    rl.c.rl_event_hook = sigEvent;
    rl.c.rl_catch_signals = 0;
}

pub fn resetPrompt() void {
    _ = rl.c.rl_on_new_line();
    _ = rl.c.rl_replace_line("", 0);
    _ = rl.c.rl_redisplay();
}

fn clearArena(arena: *std.heap.ArenaAllocator, command_line: []const u8) void {
    arena_size += command_line.len;
    if (arena_size > ARENA_REINIT_THRESHOLD) {
        _ = arena.reset(.free_all);
    } else {
        _ = arena.reset(.retain_capacity);
    }
}
