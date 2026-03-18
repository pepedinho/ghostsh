const std = @import("std");
const rl = @import("../readline.zig");

pub fn initHistory(allocator: std.mem.Allocator) void {
    const content = std.fs.cwd().readFileAlloc(allocator, "history.txt", 1024 * 1024) catch return;
    defer allocator.free(content);

    var it = std.mem.splitScalar(u8, content, '\n');

    while (it.next()) |line| {
        if (line.len == 0) continue;

        const c_line = allocator.dupeZ(u8, line) catch return;
        defer allocator.free(c_line);

        rl.c.add_history(c_line.ptr);
    }
}

pub fn appendHistory(line: []const u8) void {
    const file = std.fs.cwd().openFile("history.txt", .{ .mode = .write_only }) catch |err| switch (err) {
        error.FileNotFound => std.fs.cwd().createFile("history.txt", .{}) catch return,
        else => return,
    };
    defer file.close();

    file.seekFromEnd(0) catch return;
    file.writeAll(line) catch return;
    file.writeAll("\n") catch return;
}
