const std = @import("std");

pub const Command = struct {
    heredoc: bool,
    open_quotes: bool,
    name: []u8,
    args: [][]u8,

    pub fn deinit(self: Command, allocator: std.mem.Allocator) void {
        allocator.free(self.args);
    }
};

fn find(line: []const u8, target: u8) ?usize {
    for (line, 0..) |c, i| {
        if (c == target)
            return i;
    }
    return null;
}

fn skipToNext(line: []const u8, i: usize, target: u8) ?usize {
    const rest = line[i + 1 ..];
    const found = find(rest, target) orelse return null;
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

pub fn parse(command_line: []const u8) void {
    if (!check_unclose_elements(command_line)) {
        // std.debug.print("unclose dquotes find\n", .{});
    }
}
