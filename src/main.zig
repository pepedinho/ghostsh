const std = @import("std");
const builtin = @import("builtin");
const rl = @import("prompt/prompt.zig");
const logger = @import("logger/logger.zig");

fn handleSig(sig_num: c_int) callconv(.c) void {
    std.log.debug("SIGNAL: {d}", .{sig_num});
}

fn handleSigInt(sig_num: c_int) callconv(.c) void {
    _ = sig_num;
    rl.sigint_received.store(true, .monotonic);
    _ = rl.rlDone();
}

pub fn main() !void {
    const action = std.posix.Sigaction{
        .handler = .{ .handler = handleSigInt },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    std.posix.sigaction(std.posix.SIG.INT, &action, null);
    // std.posix.sigaction(std.posix.SIG.TERM, &action, null);
    // std.posix.sigaction(std.posix.SIG.USR1, &action, null);

    const buffer: [4096]u8 = undefined;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("[!]GSH: MEMORY LEAKS DETECTED\n", .{});
            std.posix.exit(42);
        }
        if (deinit_status == .ok) {}
    }
    const heap_allocator = gpa.allocator();

    const fallback = std.heap.stackFallback(buffer.len, heap_allocator);
    const allocator = fallback.fallback_allocator;

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    _ = args_iter.skip();

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            logger.is_on = true;
        }
    }

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    try rl.receivePrompt(allocator, &env_map);
}
