pub const NodeType = enum {
    Command,
    Pipe,
    LogicalAnd,
    LogicalOr,
    Redirect,
};

pub const Node = struct {
    tag: NodeType,
    left: ?*Node = null,
    right: ?*Node = null,
    args: ?[]const []const u8 = null,
    redirect_file: ?[]const u8 = null,
};
