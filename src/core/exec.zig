pub const Separator = enum {
    Command,
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

const std = @import("std");
const token = @import("../parsing/token.zig");
const Token = token.Token;
const NO_PRIO: u8 = 255;

fn get_priority(tok: Token) u8 {
    return switch (tok) {
        .LRedir, .RRedir, .Heredoc, .ARRedir => 3,
        .Pipe => 2,
        .And => 1,
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

pub fn build_tree(tokens: []Token, allocator: std.mem.Allocator) !*Node {
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
        const kind = fromTokenToOp(tokens[idx]);

        node.* = .{
            .Op = .{
                .kind = kind.?,
                .left = try build_tree(left, allocator),
                .right = try build_tree(right, allocator),
            },
        };
    } else {
        var args = try allocator.alloc([]const u8, tokens.len);

        for (tokens, 0..) |tok, i| {
            args[i] = switch (tok) {
                .Word => |w| switch (w) {
                    .Command => |s| s,
                    .Arg => |s| s,
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
