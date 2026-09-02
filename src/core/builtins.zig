const std = @import("std");
const logger = @import("../logger/logger.zig");

pub fn cd(argv: []const []const u8, io: std.Io, allocator: std.mem.Allocator, env: *std.process.Environ.Map) u8 {
    // const target = if (argv.len == 0) env.get("HOME").?  else argv[0];

    const target_path = if (argv.len == 0) blk: {
        if (env.get("HOME")) |home| break :blk home;
        std.debug.print("gsh: cd: HOME not set\n", .{});
        return 1;
    } else argv[0];

    const old_pwd = std.process.currentPathAlloc(io, allocator) catch |err| {
        std.debug.print("gsh: failed to read old directory: {s}\n", .{@errorName(err)});
        return 1;
    };

    defer allocator.free(old_pwd);

    var target_dir = std.Io.Dir.cwd().openDir(io, target_path, .{}) catch |err| {
        std.debug.print("cd {s} : {s}", .{target_path, @errorName(err)});
        return 1;
    };
    defer target_dir.close(io);

    std.process.setCurrentDir(io, target_dir) catch |err| {
        std.debug.print("cd {s}: {s}\n", .{ target_path, @errorName(err) });
        return 1;
    };

    const new_pwd = std.process.currentPathAlloc(io, allocator) catch |err| {
        std.debug.print("gsh: failed to read new directory: {s}\n", .{@errorName(err)});
        return 1;
    };

    defer allocator.free(new_pwd);

    if (old_pwd.len > 0) {
        env.put("OLDPWD", old_pwd) catch |err| {
            std.debug.print("gsh: {s}\n", .{@errorName(err)});
            return 1;
        };
    }
    env.put("PWD", new_pwd) catch |err| {
        std.debug.print("gsh: {s}\n", .{@errorName(err)});
        return 1;
    };

    return 0;
}
