const std = @import("std");
const builtin = @import("builtin");
const rl = @import("prompt/prompt.zig");

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{
    //     .safety = builtin.mode == .Debug,
    // }){};
    try rl.receivePrompt();
}
