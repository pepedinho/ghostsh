const std = @import("std");
const token = @import("../parsing/token.zig");

const Token = token.Token;
const debugPrint = token.debugPrint;

pub fn printToken(tokens: []token.Token) void {
    for (tokens) |tok| {
        debugPrint(tok);
    }
}
