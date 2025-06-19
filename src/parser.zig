const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;

pub const Operation = union(enum) {
    add_ptr: c_longlong,
    add_data: c_longlong,
    output,
    input,
    /// operations contained between '[' and ']'
    while_nonzero: std.ArrayList(Operation),

    fn deinit(operation: *Operation) void {
        switch (operation.*) {
            .while_nonzero => |*operations| deinitList(operations),
            else => {},
        }
    }

    fn deinitList(operations: *std.ArrayList(Operation)) void {
        for (operations.items) |*op| {
            op.deinit();
        }
        operations.deinit();
    }
};

pub const Parser = struct {
    operations: std.ArrayList(Operation),

    fn parseJumpIfZero(tokens: anytype, allocator: std.mem.Allocator) !std.ArrayList(Operation) {
        var operations = std.ArrayList(Operation).init(allocator);
        errdefer Operation.deinitList(&operations);

        while (tokens.next()) |token| {
            switch (@as(Token, token)) {
                .increment_ptr => try operations.append(.{ .add_ptr = 1 }),
                .decrement_ptr => try operations.append(.{ .add_ptr = -1 }),
                .increment_data => try operations.append(.{ .add_data = 1 }),
                .decrement_data => try operations.append(.{ .add_data = -1 }),
                .output => try operations.append(.output),
                .input => try operations.append(.input),
                .jump_if_zero => try operations.append(.{
                    .while_nonzero = try parseJumpIfZero(tokens, allocator),
                }),
                .jump_if_nonzero => return operations,
            }
        }

        return error.UnexpectedEof;
    }

    pub fn parse(tokens: anytype, allocator: std.mem.Allocator) !Parser {
        var operations = std.ArrayList(Operation).init(allocator);
        errdefer Operation.deinitList(&operations);

        while (tokens.next()) |token| {
            switch (@as(Token, token)) {
                .increment_ptr => try operations.append(.{ .add_ptr = 1 }),
                .decrement_ptr => try operations.append(.{ .add_ptr = -1 }),
                .increment_data => try operations.append(.{ .add_data = 1 }),
                .decrement_data => try operations.append(.{ .add_data = -1 }),
                .output => try operations.append(.output),
                .input => try operations.append(.input),
                .jump_if_zero => try operations.append(.{
                    .while_nonzero = try parseJumpIfZero(tokens, allocator),
                }),
                .jump_if_nonzero => return error.UnexpectedNonzeroJump,
            }
        }

        return .{ .operations = operations };
    }

    pub fn deinit(parser: *Parser) void {
        Operation.deinitList(&parser.operations);
    }
};

test Parser {
    var tok = tokenizer.Tokenizer.init("++-><[.],");
    var parser = try Parser.parse(&tok, std.testing.allocator);
    defer parser.deinit();

    var inner = std.ArrayList(Operation).init(std.testing.allocator);
    defer inner.deinit();

    try inner.appendSlice(&.{.output});

    try std.testing.expectEqualDeep(&[_]Operation{
        .{ .add_data = 1 },
        .{ .add_data = 1 },
        .{ .add_data = -1 },
        .{ .add_ptr = 1 },
        .{ .add_ptr = -1 },
        .{ .while_nonzero = inner },
        .input,
    }, parser.operations.items);
}
