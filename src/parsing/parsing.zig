const std = @import("std");
const token = @import("token.zig");
const utils = @import("utils.zig");

const ArrayList = std.ArrayList;

pub const ParseError = error{
    InvalidRedirection, // e.g  > |
    DanglingOperator, // e.g ls > (nothing)
    EmptyCommand,
    UnexpectedOperator,
};

fn print_error(target: u8) void {
    std.debug.print("unclosed '{c}'\n", .{target});
}

fn checkUncloseElements(line: []const u8) bool {
    var i: usize = 0;

    while (i < line.len) {
        const c = line[i];
        switch (c) {
            '"', '\'' => {
                i = utils.skipToNext(line, i, c) orelse {
                    print_error(c);
                    return false;
                };
            },
            '(' => {
                i = utils.skipToNext(line, i, ')') orelse {
                    print_error('(');
                    return false;
                };
            },
            else => {},
        }

        i += 1;
    }
    return true;
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

pub fn parse(allocator: std.mem.Allocator, command_line: []const u8) !void {

    //TODO: here we need to open new readline prompt and concatenate the obtained line in the new line
    if (!checkUncloseElements(command_line)) {
        return;
    }

    const tokens = try token.lex(allocator, command_line);
    defer token.freeTokens(allocator, tokens);

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
    // token.freeTokens(allocator, tokens);
}

fn isRedir(tok: token.Token) bool {
    return switch (tok) {
        .ARRedir, .Heredoc, .LRedir, .RRedir => true,
        else => false,
    };
}
