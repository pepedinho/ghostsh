const std = @import("std");
const token = @import("token.zig");
const utils = @import("utils.zig");

const ArrayList = std.ArrayList;

pub const Command = struct {
    heredoc: bool,
    open_quotes: bool,
    name: []u8,
    args: [][]u8,

    pub fn deinit(self: Command, allocator: std.mem.Allocator) void {
        allocator.free(self.args);
    }
};

fn skipToNext(line: []const u8, i: usize, target: u8) ?usize {
    const rest = line[i + 1 ..];
    const found = std.mem.indexOfScalar(u8, rest, target) orelse return null;
    return i + 1 + found;
}

fn print_error(target: u8) void {
    std.debug.print("unclosed '{c}'\n", .{target});
}

fn check_unclose_elements(line: []const u8) bool {
    var i: usize = 0;

    while (i < line.len) {
        const c = line[i];
        switch (c) {
            '"' => {
                i = skipToNext(line, i, '"') orelse {
                    print_error('"');
                    return false;
                };
            },
            '\'' => {
                i = skipToNext(line, i, '\'') orelse {
                    print_error('\'');
                    return false;
                };
            },
            '(' => {
                i = skipToNext(line, i, ')') orelse {
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

pub fn parse(allocator: std.mem.Allocator, command_line: []const u8) !void {
    if (!check_unclose_elements(command_line)) {
        return;
    }

    const tokens = try token.lex(allocator, command_line);
    // for (tokens, 0..) |tok, i| {
    //     switch (tok) {
    //         .Word => {
    //             if (i > 0) {
    //                 // here i will check precedent token to determine the type of the current word
    //                 switch (tokens[i - 1]) {
    //                     else => {},
    //                 }
    //             }
    //         },
    //         else => {},
    //     }
    // }
    utils.printToken(tokens);
    token.freeTokens(allocator, tokens);
}
