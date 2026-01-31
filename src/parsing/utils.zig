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
	return (char == '|'  or char == '<' or char == '>' or char == '&');
}

pub fn isSeparaor(char: u8) bool {
	return (isSpace(char) or isOperator(char));
}

pub fn printToken(tokens: []token.Token) void {
    for (tokens) |tok| {
        debugPrint(tok);
    }
}
