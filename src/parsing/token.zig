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

fn extractWord(line_lex: *LineLex, env: *const std.process.EnvMap, allocator: std.mem.Allocator) ![]const u8 {
    const line = line_lex.line;
    const start = line_lex.index;
    var is_dquotes = false;
    var len: usize = 0;

    while (!line_lex.isEnd() and !utils.isSeparaor(line_lex.currentChar())) {
        switch (line_lex.currentChar()) {
            '"', '\'' => {
                if (line_lex.currentChar() == '"' and len == 0)
                    is_dquotes = true;
                const inc = utils.skipToNext(line_lex.line, line_lex.index, line_lex.currentChar()) orelse unreachable;

                line_lex.incrementNbIndex(inc);
                len += inc;
            },
            else => {},
        }
        line_lex.incrementNbIndex(1);
        len += 1;
    }

    if (is_dquotes) {
        if (std.mem.indexOfScalar(u8, line[start .. start + len], '$')) |pos| {
            var expanded: std.ArrayList(u8) = .empty;
            try expanded.appendSlice(allocator, line[start .. start + pos]);
            const var_name = extractVarNameByIndex(line[start .. start + len], pos);
            const value = env.get(var_name) orelse "";
            try expanded.appendSlice(allocator, value);
            try expanded.appendSlice(allocator, line[start + pos + var_name.len + 1 .. start + len]);
            // std.debug.print("find '$' in dquotes at index '{d}'\n", .{pos});
            // std.debug.print("name = {s}\n", .{var_name});
            // std.debug.print("value = {s}\n", .{value});
            // std.debug.print("expanded = {s}\n", .{expanded.items});
            const res = try expanded.toOwnedSlice(allocator);
            return utils.trim(res, "\"'");
        }
    }

    return utils.trim(line[start .. start + len], "\"'");
}

fn extractVarNameByIndex(line: []const u8, index: usize) []const u8 {
    const separators = &[_]u8{
        ' ', '|',  '<', '>', '&',
        '"', '\'', 9,   10,  11,
        12,  13,
    };

    const start = index + 1;
    const rest = line[start..];
    const pos = if (std.mem.indexOfAny(u8, rest, separators)) |p| p else rest.len;

    return line[start .. start + pos];
}

//FIXME: changes separators to accept only alphanum char and '_'
fn extractVarName(line_lex: *LineLex) []const u8 {
    const separators = &[_]u8{
        ' ', '|', '<', '>', '&',
        9,   10,  11,  12,  13,
    };

    line_lex.index += 1; // eat '$'
    const line = line_lex.line;
    const start = line_lex.index;
    const rest = line[start..];
    const pos = if (std.mem.indexOfAny(u8, rest, separators)) |p| p else rest.len;

    line_lex.index += pos;
    return line[start .. start + pos];
}

pub fn lex(allocator: std.mem.Allocator, line: []const u8, env: *const std.process.EnvMap) ![]Token {
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
            '$' => {
                const word = extractVarName(&line_lex);
                const content = env.get(word) orelse "";
                const env_tokens = try lex(allocator, content, env);
                try tokens.appendSlice(allocator, env_tokens);
            },
            else => {
                const word = try extractWord(&line_lex, env, allocator);
                try tokens.append(allocator, Token{ .Word = Word{ .Undefined = word } });
            },
        }
    }

    return tokens.toOwnedSlice(allocator);
}
