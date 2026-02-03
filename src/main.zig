const std = @import("std");
const builtin = @import("builtin");
const rl = @import("prompt/prompt.zig");

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{
    //     .safety = builtin.mode == .Debug,
    // }){};

    const buffer: [4096]u8 = undefined;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const heap_allocator = gpa.allocator();

    const fallback = std.heap.stackFallback(buffer.len, heap_allocator);
    const allocator = fallback.fallback_allocator;

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    var it = env_map.iterator();

    while (it.next()) |entry| {
        std.debug.print("{s} = {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    try rl.receivePrompt();
}
