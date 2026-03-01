const std = @import("std");
const token = @import("token.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "Lexer: basic command with arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var env = std.process.EnvMap.init(allocator);

    const input = "ls -l /tmp";
    const tokens = try token.lex(allocator, input, &env);

    try expect(tokens.len == 3);
    try expect(tokens[0] == .Word);
    try expectEqualStrings("ls", tokens[0].Word.Undefined);
}

test "Lexer: expansion and quotes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var env = std.process.EnvMap.init(allocator);

    try env.put("USER", "pepedinho");
    const input = "echo \"hello $USER\"";
    const tokens = try token.lex(allocator, input, &env);

    try expectEqualStrings("echo", tokens[0].Word.Undefined);
    try expectEqualStrings("hello pepedinho", tokens[1].Word.Undefined);
}

test "Utils: trim function" {
    const utils = @import("utils.zig");
    try expectEqualStrings("hello", utils.trim("\"'hello'\"", "\"'"));
    try expectEqualStrings("", utils.trim("\"\"\"", "\""));
}
