const std = @import("std");
const token = @import("../parsing/token.zig");

const Token = token.Token;
const debugPrint = token.debugPrint;

pub fn isSpace(char: u8) bool {
    return (char >= 9 and char <= 13 or char == 32);
}

pub fn skipToNext(line: []const u8, i: usize, target: u8) ?usize {
    const rest = line[i + 1 ..];
    const found = std.mem.indexOfScalar(u8, rest, target) orelse return null;
    return 1 + found;
}

pub fn isOperator(char: u8) bool {
    return (char == '|' or char == '<' or char == '>' or char == '&');
}

pub fn isSeparaor(char: u8) bool {
    return (isSpace(char) or isOperator(char));
}

pub fn printToken(tokens: []token.Token) void {
    for (tokens) |tok| {
        debugPrint(tok);
    }
}

pub fn trim(str: []const u8, target: []const u8) []const u8 {
    if (target.len == 0)
        return str;

    var start: usize = 0;
    var end: usize = str.len;

    while (start < end and std.mem.indexOfScalar(u8, target, str[start]) != null) {
        start += 1;
    }

    while (end > start and std.mem.indexOfScalar(u8, target, str[end - 1]) != null) {
        end -= 1;
    }

    return str[start..end];
}
