pub const Separator = enum {
    Pipe,
    LogicalAnd,
    LogicalOr,
    Redirect,
};

pub const Node = union(enum) {
    Command: struct {
        args: []const []const u8,
        redirect_file: ?[]const u8 = null,
    },

    Op: struct {
        kind: Separator,
        left: *Node,
        right: *Node,
    },
};

pub const ExecError = error{
    InvalidSeparator,
};

const std = @import("std");
const token = @import("../parsing/token.zig");
const Token = token.Token;
const NO_PRIO: u8 = 255;

fn get_priority(tok: Token) u8 {
    return switch (tok) {
        .LRedir, .RRedir, .Heredoc, .ARRedir => 3,
        .Pipe => 2,
        .And, .AndAnd => 1,
        else => NO_PRIO,
    };
}

fn fromTokenToOp(tok: Token) ?Separator {
    return switch (tok) {
        .ARRedir, .Heredoc, .LRedir, .RRedir => Separator.Redirect,
        .Pipe => Separator.Pipe,
        .AndAnd => Separator.LogicalAnd,
        .And, .Word => null,
    };
}

pub fn build_tree(tokens: []const Token, allocator: std.mem.Allocator) !*Node {
    var last_priority: u8 = NO_PRIO;
    var split_index: ?usize = null;

    for (tokens, 0..) |tok, i| {
        const prio = get_priority(tok);
        if (prio != NO_PRIO and prio <= last_priority) {
            last_priority = prio;
            split_index = i;
        }
    }

    const node = try allocator.create(Node);

    if (split_index) |idx| {
        std.debug.print("top of the tree : tokens[{d}]\n", .{idx});
        const left = tokens[0..idx];
        const right = tokens[idx + 1 ..];
        const kind = fromTokenToOp(tokens[idx]) orelse {
            return ExecError.InvalidSeparator;
        };

        node.* = .{
            .Op = .{
                .kind = kind,
                .left = try build_tree(left, allocator),
                .right = try build_tree(right, allocator),
            },
        };
    } else {
        var args = try allocator.alloc([]const u8, tokens.len);

        for (tokens, 0..) |tok, i| {
            args[i] = switch (tok) {
                .Word => |w| switch (w) {
                    .Command, .Arg, .File => |s| s,
                    //INFO: for now .File is not implemented
                    else => unreachable,
                },
                else => unreachable,
            };
        }

        std.debug.print("leaf : [{s}]\n", .{args[0]});

        node.* = .{
            .Command = .{
                .args = args,
                .redirect_file = null,
            },
        };
    }

    return node;
}

fn convertEnvToPosix(env: *const std.process.EnvMap, allocator: std.mem.Allocator) ![*:null]const ?[*:0]const u8 {
    var envp_array = try allocator.alloc(?[*:0]const u8, env.count() + 1);

    var iter = env.iterator();
    var env_idx: usize = 0;

    while (iter.next()) |entry| {
        const tmp_str = try std.fmt.allocPrint(allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* });
        defer allocator.free(tmp_str);

        const env_str = try allocator.dupeZ(u8, tmp_str);

        envp_array[env_idx] = env_str.ptr;
        env_idx += 1;
    }
    envp_array[env.count()] = null;

    return @ptrCast(envp_array.ptr);
}

pub fn execTree(node: *Node, allocator: std.mem.Allocator, env: *const std.process.EnvMap) !void {
    switch (node.*) {
        .Command => |cmd| {
            if (cmd.args.len == 0) return;

            // std.debug.print("prepare command: {s}\n", .{cmd.args[0]});

            var argv = try allocator.alloc(?[*:0]const u8, cmd.args.len + 1);

            for (cmd.args, 0..) |arg, i| {
                argv[i] = (try allocator.dupeZ(u8, arg)).ptr;
            }
            argv[cmd.args.len] = null;
            const envp = try convertEnvToPosix(env, allocator);

            const pid = try std.posix.fork();
            if (pid == 0) {
                const file = argv[0].?;
                const argv_ptr: [*:null]const ?[*:0]const u8 = @ptrCast(argv.ptr);

                const err = std.posix.execvpeZ(file, argv_ptr, envp);

                std.debug.print("gsh: {s}: {s}\n", .{ cmd.args[0], @errorName(err) });
                std.posix.exit(1);
            } else {
                _ = std.posix.waitpid(pid, 0);
            }
        },
        .Op => |op| {
            switch (op.kind) {
                .Pipe => {
                    std.debug.print("create pipe\n", .{});
                    const pipe = try std.posix.pipe();

                    const left_pid = try std.posix.fork();
                    if (left_pid == 0) {
                        try std.posix.dup2(pipe[1], std.posix.STDOUT_FILENO);

                        std.posix.close(pipe[0]);
                        std.posix.close(pipe[1]);

                        try execTree(op.left, allocator, env);
                        std.posix.exit(0);
                    }

                    const right_pid = try std.posix.fork();
                    if (right_pid == 0) {
                        try std.posix.dup2(pipe[0], std.posix.STDIN_FILENO);

                        std.posix.close(pipe[0]);
                        std.posix.close(pipe[1]);

                        try execTree(op.right, allocator, env);
                        std.posix.exit(0);
                    }

                    std.posix.close(pipe[0]);
                    std.posix.close(pipe[1]);

                    _ = std.posix.waitpid(left_pid, 0);
                    _ = std.posix.waitpid(right_pid, 0);
                },
                .LogicalAnd => {
                    std.debug.print("eval logical and\n", .{});

                    //TODO: execTree(left)
                    //if not failed -> execTree(right)
                },
                .LogicalOr => {
                    //TODO: same as AND but execut right only if left failed
                },
                .Redirect => {
                    //TODO: open(), dup2() STDIN/STDOUT, execTree(left)
                    const filename = op.right.Command.args[0];
                    const file_z = try allocator.dupeZ(u8, filename);

                    const flags = std.posix.O{
                        .ACCMODE = .WRONLY,
                        .CREAT = true,
                        .TRUNC = true,
                    };

                    const fd = std.posix.openZ(file_z, flags, 0o666) catch |err| {
                        std.debug.print("gsh: {s}: {s}\n", .{ filename, @errorName(err) });
                        return;
                    };

                    const og_stdout = try std.posix.dup(std.posix.STDOUT_FILENO);

                    try std.posix.dup2(fd, std.posix.STDOUT_FILENO);
                    std.posix.close(fd);
                    defer {
                        std.posix.dup2(og_stdout, std.posix.STDOUT_FILENO) catch |err| {
                            std.debug.print("gsh: erreur critique en restaurant stdout: {s}\n", .{@errorName(err)});
                        };
                        std.posix.close(og_stdout);
                    }

                    try execTree(op.left, allocator, env);
                },
            }
        },
    }
}
