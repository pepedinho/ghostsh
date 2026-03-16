const std = @import("std");
const parser = @import("../parsing/parsing.zig");
const rl = @import("../readline.zig");

// Number of bytes of accumulated command input after which we force a full
// arena reset (free_all) to prevent unbounded memory growth.
const ARENA_REINIT_THRESHOLD = 1000;
var arena_size: usize = 0;
pub var sigint_received = std.atomic.Value(bool).init(false);

fn readPipeLine(allocator: std.mem.Allocator) !?[]const u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    var byte: [1]u8 = undefined;
    while (true) {
        const byte_read = try std.posix.read(std.posix.STDIN_FILENO, &byte);

        if (byte_read == 0) {
            if (list.items.len == 0) return null;
            break;
        }

        if (byte[0] == '\n') break;
        try list.append(allocator, byte[0]);
    }

    const slice = try list.toOwnedSlice(allocator);

    return slice;
}

pub fn receivePrompt(allocator: std.mem.Allocator, env: *std.process.EnvMap) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const is_interactive = std.posix.isatty(std.posix.STDIN_FILENO);

    if (is_interactive) {
        initReadline();
    }

    while (true) {
        const arena_allocator = arena.allocator();
        var command_line: ?[]const u8 = null;
        var used_readline = false;

        if (is_interactive) {
            if (rl.readline(arena_allocator, "gsh> ")) |line| {
                command_line = line;
                used_readline = true;
            } else {
                if (sigint_received.load(.monotonic)) {
                    _ = sigint_received.swap(false, .monotonic);
                    continue;
                }
                std.debug.print("exit\n", .{});
                return;
            }
        } else {
            command_line = readPipeLine(arena_allocator) catch |err| {
                std.debug.print("gsh: read error: {s}\n", .{@errorName(err)});
                return;
            };

            if (command_line == null) {
                return;
            }
        }

        if (sigint_received.swap(false, .monotonic)) {
            if (used_readline) rl.free(command_line.?);
            continue;
        }

        if (command_line) |cmd| {
            if (cmd.len > 0) {
                parser.parse(arena_allocator, cmd, env) catch |err| {
                    std.debug.print("gsh: error: {s}\n", .{@errorName(err)});
                };
            }

            if (used_readline) {
                rl.free(cmd);
            }

            clearArena(&arena, cmd);
        }
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

fn clearArena(arena: *std.heap.ArenaAllocator, command_line: []const u8) void {
    arena_size += command_line.len;
    if (arena_size > ARENA_REINIT_THRESHOLD) {
        _ = arena.reset(.free_all);
    } else {
        _ = arena.reset(.retain_capacity);
    }
}
