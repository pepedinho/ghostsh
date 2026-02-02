const std = @import("std");
const ArrayList = std.ArrayList;
const utils = @import("utils.zig");

pub const LineLex = struct {
    line: []const u8,
    index: usize,

    pub fn isEnd(self: LineLex) bool {
        return (self.index >= self.line.len);
    }

    pub fn currentChar(self: LineLex) u8 {
        return (self.line[self.index]);
    }

    pub fn incrementNbIndex(self: *LineLex, nb: usize) void {
        self.index += nb;
    }

    pub fn lookAhead(self: LineLex) ?u8 {
        if (self.index + 1 >= self.line.len) return null;
        return (self.line[self.index + 1]);
    }
};

pub const Error = error{NoSpaceFound};

pub const Token = union(enum) {
    Pipe, // |
    // Or, // ||
    Word: Word,
    Heredoc, // <<
    LRedir, // <
    RRedir, // >
    ARRedir, // >>
    And, // &
    AndAnd, // &&
};

pub const Word = union(enum) {
    Command: []const u8,
    Arg: []const u8,
    File: []const u8,
    Undefined: []const u8,
};

pub fn debugPrint(token: Token) void {
    switch (token) {
        .Pipe => {
            std.debug.print("Token::Pipe\n", .{});
        },
        .Heredoc => {
            std.debug.print("Token::Heredoc\n", .{});
        },
        .LRedir => {
            std.debug.print("Token::LRedir\n", .{});
        },
        .RRedir => {
            std.debug.print("Token::RRedir\n", .{});
        },
        .ARRedir => {
            std.debug.print("Token::ARRedir\n", .{});
        },
        .And => {
            std.debug.print("Token::And\n", .{});
        },
        .AndAnd => {
            std.debug.print("Token::AndAnd\n", .{});
        },
        .Word => |word_union| {
            switch (word_union) {
                .Command => |word| std.debug.print("Token::Word::Command(\"{s}\")\n", .{word}),
                .Arg => |word| std.debug.print("Token::Word::Arg(\"{s}\")\n", .{word}),
                .File => |word| std.debug.print("Token::Word::File(\"{s}\")\n", .{word}),
                .Undefined => |word| std.debug.print("Token::Word::Undefined(\"{s}\")\n", .{word}),
            }
        },
    }
}

fn extractWord(line_lex: LineLex) ![]const u8 {
    const separators = &[_]u8{
        ' ', '|', '<', '>', '&',
        9,   10,  11,  12,  13,
    };

    const line = line_lex.line;
    const start = line_lex.index;
    const rest = line_lex.line[start..];
    const pos = if (std.mem.indexOfAny(u8, rest, separators)) |p| p else rest.len;

    return line[start .. start + pos];
}

pub fn lex(allocator: std.mem.Allocator, line: []const u8) ![]Token {
    var line_lex = LineLex{ .line = line, .index = 0 };

    var tokens: ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);
    while (!line_lex.isEnd()) {
        while (!line_lex.isEnd() and utils.isSpace(line_lex.currentChar())) : (line_lex.incrementNbIndex(1)) {}
        if (line_lex.isEnd()) break;

        const c = line_lex.currentChar();
        switch (c) {
            '|' => {
                try tokens.append(allocator, Token.Pipe);
                line_lex.incrementNbIndex(1);
            },
            '<' => {
                if (line_lex.lookAhead() == '<') {
                    try tokens.append(allocator, Token.Heredoc);
                    line_lex.incrementNbIndex(2);
                    continue;
                }
                try tokens.append(allocator, Token.LRedir);
                line_lex.incrementNbIndex(1);
            },
            '>' => {
                if (line_lex.lookAhead() == '>') {
                    try tokens.append(allocator, Token.ARRedir);
                    line_lex.incrementNbIndex(2);
                    continue;
                }
                try tokens.append(allocator, Token.RRedir);
                line_lex.incrementNbIndex(1);
            },
            '&' => {
                if (line_lex.lookAhead() == '&') {
                    try tokens.append(allocator, Token.AndAnd);
                    line_lex.incrementNbIndex(2);
                    continue;
                }
                try tokens.append(allocator, Token.And);
                line_lex.incrementNbIndex(1);
            },
            else => {
                const word = try extractWord(line_lex);
                if (word.len == 0) {
                    line_lex.incrementNbIndex(1);
                    continue;
                }

                try tokens.append(allocator, Token{ .Word = Word{ .Undefined = word } });
                line_lex.incrementNbIndex(word.len);
            },
        }
    }

    return tokens.toOwnedSlice(allocator);
}
