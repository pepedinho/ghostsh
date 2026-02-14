const std = @import("std");
const token = @import("token.zig");
const utils = @import("utils.zig");
const rl = @import("../readline.zig");

const ArrayList = std.ArrayList;

pub const ParseError = error{
    InvalidRedirection, // e.g  > |
    DanglingOperator, // e.g ls > (nothing)
    EmptyCommand,
    UnexpectedOperator,
};

fn skipToNext(line: []const u8, i: usize, target: u8) ?usize {
    const rest = line[i + 1 ..];
    const found = std.mem.indexOfScalar(u8, rest, target) orelse return null;
    return i + 1 + found;
}

fn getNewLine(allocator: std.mem.Allocator, command_line: []const u8, prompt: []const u8) []const u8 {
    const next_line = rl.readline(allocator, prompt) orelse unreachable;

    defer rl.free(next_line);

    var new_line = allocator.alloc(u8, command_line.len + next_line.len + 1) catch unreachable;

    @memmove(new_line[0..command_line.len], command_line);
    new_line[command_line.len] = '\n';
    @memmove(new_line[command_line.len + 1 ..], next_line);

    return new_line;
}

fn checkUncloseElements(allocator: std.mem.Allocator, line: []const u8) []const u8 {
    var i: usize = 0;

    while (i < line.len) : (i += 1) {
        const c = line[i];
        switch (c) {
            '"', '\'' => {
                i += utils.skipToNext(line, i, c) orelse {
                    const prompt = if (c == '\'') "quote> " else "dquote> ";
                    const new_line = getNewLine(allocator, line, prompt);
                    return checkUncloseElements(allocator, new_line);
                };
            },
            '(' => {
                i += utils.skipToNext(line, i, ')') orelse {
                    const new_line = getNewLine(allocator, line, "subshell> ");
                    return checkUncloseElements(allocator, new_line);
                };
            },
            else => {},
        }
    }
    return line;
}

fn resolveWord(tokens: []token.Token, i: usize, str: []const u8) token.Word {
    if (i == 0) return .{ .Command = str };

    return switch (tokens[i - 1]) {
        .LRedir, .RRedir, .ARRedir, .Heredoc => .{ .File = str },
        .Pipe, .And, .AndAnd => .{ .Command = str },
        .Word => |prev_w| switch (prev_w) {
            //FIXME: This is not exact, after a file a word can be a Command or an Arg depending on the last word kind
            .File => .{ .Command = str },
            else => .{ .Arg = str },
        },
    };
}

pub fn parse(allocator: std.mem.Allocator, command_line: []const u8, env: *const std.process.EnvMap) !void {
    const full_line = checkUncloseElements(allocator, command_line);

    const tokens = try token.lex(allocator, full_line, env);

    if (tokens.len == 0) return;

    for (tokens, 0..) |*tok, i| {
        switch (tok.*) {
            .Pipe, .And, .AndAnd => {
                if (i == 0) return error.UnexpectedOperator;
                if (i > 0 and isRedir(tokens[i - 1])) return error.InvalidRedirection;
                if (i == tokens.len - 1) return error.EmptyCommand;
                const next_token = tokens[i + 1];
                switch (next_token) {
                    .Pipe, .RRedir, .ARRedir, .Heredoc, .And, .AndAnd => return error.UnexpectedOperator,
                    else => {},
                }
            },
            .LRedir, .RRedir, .ARRedir, .Heredoc => {
                if (i > 0 and isRedir(tokens[i - 1])) return error.InvalidRedirection;
                if (i == tokens.len - 1) return error.DanglingOperator;
            },
            .Word => |w| {
                const str = switch (w) {
                    inline else => |s| s,
                };
                tok.* = .{ .Word = resolveWord(tokens, i, str) };
            },
        }
    }
    utils.printToken(tokens);
}

fn isRedir(tok: token.Token) bool {
    return switch (tok) {
        .ARRedir, .Heredoc, .LRedir, .RRedir => true,
        else => false,
    };
}
