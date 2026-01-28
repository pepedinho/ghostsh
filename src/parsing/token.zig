const std = @import("std");
const ArrayList = std.ArrayList;

pub const Error = error{NoSpaceFound};

pub const Token = union(enum) {
    Pipe, // |
    Word: Word,
    Heredoc, // <<
    LRedir, // <
    RRedir, // >
    ARRedir, // >>
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

fn extractWord(allocator: std.mem.Allocator, line: []const u8, i: usize) ![]const u8 {
    const separators = " |<>";
    const rest = line[i..];
    const pos = if (std.mem.indexOfAny(u8, rest, separators)) |p| p else rest.len;

    return try allocator.dupe(u8, line[i .. i + pos]);
}

pub fn freeTokens(allocator: std.mem.Allocator, tokens: []Token) void {
    for (tokens) |token| {
        switch (token) {
            .Word => |word_union| {
                switch (word_union) {
                    inline else => |slice| allocator.free(slice),
                }
            },
            else => {},
        }
    }
    allocator.free(tokens);
}

pub fn lex(allocator: std.mem.Allocator, line: []const u8) ![]Token {
    var i: usize = 0;
    var tokens: ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);
    while (i < line.len) {
        while (i < line.len and line[i] == ' ') : (i += 1) {}
        if (i >= line.len) break;

        const c = line[i];
        switch (c) {
            '|' => {
                try tokens.append(allocator, Token.Pipe);
                i += 1;
            },
            '<' => {
                try tokens.append(allocator, Token.LRedir);
                i += 1;
            },
            '>' => {
                try tokens.append(allocator, Token.RRedir);
                i += 1;
            },
            else => {
                const word = try extractWord(allocator, line, i);
                if (word.len == 0) {
                    allocator.free(word);
                    i += 1;
                    continue;
                }

                try tokens.append(allocator, Token{ .Word = Word{ .Undefined = word } });
                i += word.len;
            },
        }
    }

    return tokens.toOwnedSlice(allocator);
}
