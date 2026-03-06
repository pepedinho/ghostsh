const std = @import("std");
const Token = @import("../parsing/token.zig").Token;
const core = @import("exec.zig");

test "AST: simple tree with pipe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const tokens = [_]Token{
        .{ .Word = .{ .Command = "cat" } },
        .{ .Word = .{ .Arg = "oui" } },
        .Pipe,
        .{ .Word = .{ .Command = "grep" } },
        .{ .Word = .{ .Arg = "non" } },
    };

    const tree = try core.build_tree(&tokens, allocator);

    try std.testing.expectEqual(.Op, std.meta.activeTag(tree.*));
    try std.testing.expectEqual(core.Separator.Pipe, tree.Op.kind);

    try std.testing.expectEqual(.Command, std.meta.activeTag(tree.Op.left.*));
    try std.testing.expectEqualStrings("cat", tree.Op.left.Command.args[0]);
    try std.testing.expectEqualStrings("oui", tree.Op.left.Command.args[1]);

    try std.testing.expectEqual(.Command, std.meta.activeTag(tree.Op.right.*));
    try std.testing.expectEqualStrings("grep", tree.Op.right.Command.args[0]);
}

test "AST: simple command without operators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokens = [_]Token{
        .{ .Word = .{ .Command = "ls" } },
        .{ .Word = .{ .Arg = "-l" } },
        .{ .Word = .{ .Arg = "-a" } },
    };

    const tree = try core.build_tree(&tokens, allocator);

    try std.testing.expectEqual(.Command, std.meta.activeTag(tree.*));

    try std.testing.expectEqual(@as(usize, 3), tree.Command.args.len);
    try std.testing.expectEqualStrings("ls", tree.Command.args[0]);
    try std.testing.expectEqualStrings("-l", tree.Command.args[1]);
    try std.testing.expectEqualStrings("-a", tree.Command.args[2]);
}

test "AST: left associativity with multiple pipes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokens = [_]Token{
        .{ .Word = .{ .Command = "cmd1" } },
        .Pipe,
        .{ .Word = .{ .Command = "cmd2" } },
        .Pipe,
        .{ .Word = .{ .Command = "cmd3" } },
    };

    const tree = try core.build_tree(&tokens, allocator);

    try std.testing.expectEqual(.Op, std.meta.activeTag(tree.*));
    try std.testing.expectEqual(core.Separator.Pipe, tree.Op.kind);

    try std.testing.expectEqual(.Command, std.meta.activeTag(tree.Op.right.*));
    try std.testing.expectEqualStrings("cmd3", tree.Op.right.Command.args[0]);

    const left_node = tree.Op.left;
    try std.testing.expectEqual(.Op, std.meta.activeTag(left_node.*));
    try std.testing.expectEqual(core.Separator.Pipe, left_node.Op.kind);

    try std.testing.expectEqual(.Command, std.meta.activeTag(left_node.Op.left.*));
    try std.testing.expectEqualStrings("cmd1", left_node.Op.left.Command.args[0]);

    try std.testing.expectEqual(.Command, std.meta.activeTag(left_node.Op.right.*));
    try std.testing.expectEqualStrings("cmd2", left_node.Op.right.Command.args[0]);
}

test "AST: logical AND operator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokens = [_]Token{
        .{ .Word = .{ .Command = "make" } },
        .AndAnd, // Adapte avec .And si c'est ce que ton lexer génère
        .{ .Word = .{ .Command = "./run" } },
    };

    const tree = try core.build_tree(&tokens, allocator);

    try std.testing.expectEqual(.Op, std.meta.activeTag(tree.*));
    try std.testing.expectEqual(core.Separator.LogicalAnd, tree.Op.kind);

    try std.testing.expectEqual(.Command, std.meta.activeTag(tree.Op.left.*));
    try std.testing.expectEqualStrings("make", tree.Op.left.Command.args[0]);

    try std.testing.expectEqual(.Command, std.meta.activeTag(tree.Op.right.*));
    try std.testing.expectEqualStrings("./run", tree.Op.right.Command.args[0]);
}
