pub const Separator = enum {
    Pipe,
    LogicalAnd,
    LogicalOr,
};

pub const Op = struct {
    kind: Separator,
    left: *Node,
    right: *Node,
};
pub const Command = struct {
    args: []const []const u8,
    in_file: ?[]const u8 = null,
    out_file: ?[]const u8 = null,
    append: bool,
};

pub const Node = union(enum) {
    Command: Command,
    Op: Op,
};

pub const ExecError = error{
    InvalidSeparator,
};

const std = @import("std");
const token = @import("../parsing/token.zig");
const Token = token.Token;
const logger = @import("../logger/logger.zig");
const NO_PRIO: u8 = 255;
const TRUNC: u8 = 0;
const APPEND: u8 = 1;

fn get_priority(tok: Token) u8 {
    return switch (tok) {
        .Pipe => 2,
        .And, .AndAnd => 1,
        else => NO_PRIO,
    };
}

fn fromTokenToOp(tok: Token) ?Separator {
    return switch (tok) {
        .Pipe => Separator.Pipe,
        .AndAnd => Separator.LogicalAnd,
        .And, .Word => null,
        else => unreachable,
    };
}

fn getWordString(tok: Token) []const u8 {
    return switch (tok) {
        .Word => |w| switch (w) {
            .Command, .Arg, .File => |s| s,
            else => unreachable,
        },
        else => unreachable,
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
        logger.debug("top of the tree : tokens[{d}]\n", .{idx});
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
        var args_list: std.ArrayList([]const u8) = .empty;
        var in_file: ?[]const u8 = null;
        var out_file: ?[]const u8 = null;
        var append = false;

        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            const tok = tokens[i];

            switch (tok) {
                .LRedir => {
                    if (i + 1 < tokens.len) {
                        in_file = getWordString(tokens[i + 1]);
                        i += 1;
                    }
                },
                .RRedir => {
                    if (i + 1 < tokens.len) {
                        out_file = getWordString(tokens[i + 1]);
                        i += 1;
                    }
                },
                .ARRedir => {
                    if (i + 1 < tokens.len) {
                        out_file = getWordString(tokens[i + 1]);
                        i += 1;
                        append = true;
                    }
                },
                .Word => {
                    const str = getWordString(tok);
                    try args_list.append(allocator, str);
                },
                else => {},
            }
        }

        const args = try args_list.toOwnedSlice(allocator);

        if (args.len > 0) {
            logger.debug("leaf : [{s}]\n", .{args[0]});
        }

        node.* = .{
            .Command = .{
                .args = args,
                .in_file = in_file,
                .out_file = out_file,
                .append = append,
            },
        };
    }

    return node;
}

fn convertEnvToPosix(env: *std.process.Environ.Map, allocator: std.mem.Allocator) ![*:null]const ?[*:0]const u8 {
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

const builtin = @import("builtins.zig");

fn checkBuiltIn(io: std.Io, cmd: []const u8, argv: []const []const u8, allocator: std.mem.Allocator, env: *std.process.Environ.Map)?u8 {
    if (std.mem.eql(u8, cmd, "cd")) {
        return builtin.cd(argv, io, allocator, env);
    }

    return null;
}

pub fn execTree(io: std.Io, node: *Node, allocator: std.mem.Allocator, env: *std.process.Environ.Map) !u8 {
    switch (node.*) {
        .Command => |cmd| {
            if (cmd.args.len == 0) return 0;

            // std.debug.print("prepare command: {s}\n", .{cmd.args[0]});

            logger.debug("cmd.len: {d}\n", .{cmd.args.len});
            const bt = checkBuiltIn(io, cmd.args[0], cmd.args[1..], allocator, env);

            if (bt != null) {
                return bt.?;
            }

            var argv = try allocator.alloc(?[*:0]const u8, cmd.args.len + 1);

            for (cmd.args, 0..) |arg, i| {
                argv[i] = (try allocator.dupeZ(u8, arg)).ptr;
            }
            argv[cmd.args.len] = null;
            const envp = try convertEnvToPosix(env, allocator);

            const pid = std.c.fork();
            if (pid < 0) {
                const err = std.c.errno(pid);
                std.debug.print("gsh: {s}\n", .{err});
            }
            if (pid == 0) {
                if (cmd.in_file) |in_file| {
                    const file_z = try allocator.dupeZ(u8, in_file);
                    const flags = std.posix.O{ .ACCMODE = .RDONLY };
                    
                    const fd = std.c.open(file_z, flags);
                    if (fd < 0) {
                        std.debug.print("gsh: {s}: No such file or directory.\n", .{ in_file  });
                        std.c.exit(1);
                    }
                    if (std.c.dup2(fd, std.posix.STDOUT_FILENO) < 0) {
                        return error.Dup2Fail;
                    }
                    if (std.c.close(fd) < 0) {
                        return error.CloseFail;
                    }
                }

                if (cmd.out_file) |out_file| {
                    const file_z = try allocator.dupeZ(u8, out_file);
                    const flags = std.posix.O{
                        .ACCMODE = .WRONLY,
                        .CREAT = true,
                        .TRUNC = !cmd.append,
                        .APPEND = cmd.append,
                    };

                    const fd = std.c.open(file_z, flags, @as(c_int, 0o666));
                    if (fd < 0) {
                        std.debug.print("gsh: {s}: No such file or directory.\n", .{ out_file  });
                        std.c.exit(1);
                    }
                    if (std.c.dup2(fd, std.posix.STDOUT_FILENO) < 0) {
                        return error.Dup2Fail;
                    }
                    if (std.c.close(fd) < 0) {
                        return error.CloseFail;
            
                    }
                }

                const file = argv[0].?;
                const argv_ptr: [*:null]const ?[*:0]const u8 = @ptrCast(argv.ptr);

                const err = std.c.execve(file, argv_ptr, envp);

                std.debug.print("gsh: {s}: Failed to exec.\n", .{ cmd.args[0] });
                std.c.exit(err);
            } else {
                var status: c_int = undefined;

                //WARN: need to check waitpid return value
                _ = std.c.waitpid(pid, &status, @as(c_int, 0));

                if (std.posix.W.IFEXITED(@intCast(status))) {
                    return std.posix.W.EXITSTATUS(@intCast(status));
                }

                return 1;
            }
        },
        .Op => |*op| {
            switch (op.kind) {
                .Pipe => {
                    logger.debug("create pipe\n", .{});
                    var pipe: [2]i32 = .{ 0, 0};
                    const pipe_s = std.c.pipe(&pipe);
                    if (pipe_s < 0) {
                        const err = std.c.errno(pipe_s);
                        std.debug.print("{s}", .{err});
                    }

                    const left_pid = std.c.fork();
                    if (left_pid < 0) {
                        const err = std.c.errno(left_pid);
                        std.debug.print("gsh: {s}\n", .{err});
                    }
                    if (left_pid == 0) {
                        if (std.c.dup2(pipe[1], std.posix.STDOUT_FILENO) < 0) {
                            return error.Dup2Fail;
                        }

                        std.posix.close(pipe[0]);
                        std.posix.close(pipe[1]);

                        const left_status = try execTree(io,op.left, allocator, env);
                        std.posix.exit(@intCast(left_status));
                    }

                    const right_pid = try std.c.fork();
                    if (right_pid < 0) {
                        const err = std.c.errno(right_pid);
                        std.debug.print("gsh: {s}\n", .{err});
                    }
                    if (right_pid == 0) {
                        if (std.c.dup2(pipe[0], std.posix.STDOUT_FILENO) < 0) {
                            return error.Dup2Fail;
                        }

                        std.posix.close(pipe[0]);
                        std.posix.close(pipe[1]);

                        const right_status = try execTree(io,op.right, allocator, env);
                        std.posix.exit(@intCast(right_status));
                    }

                    std.posix.close(pipe[0]);
                    std.posix.close(pipe[1]);

                    const right_res = std.posix.waitpid(right_pid, 0);
                    _ = std.posix.waitpid(left_pid, 0);
                    if (std.posix.W.IFEXITED(right_res.status)) {
                        return std.posix.W.EXITSTATUS(right_res.status);
                    }
                    return 1;
                },
                .LogicalAnd => {
                    logger.debug("eval logical and\n", .{});

                    const left_status = try execTree(io, op.left, allocator, env);

                    if (left_status == 0) {
                        return try execTree(io, op.right, allocator, env);
                    }

                    return left_status;
                },
                .LogicalOr => {
                    const left_status = try execTree(io, op.left, allocator, env);

                    if (left_status != 0) {
                        return try execTree(io, op.right, allocator, env);
                    }

                    return left_status;
                },
            }
        },
    }
}
