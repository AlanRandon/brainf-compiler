const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;

pub const Operation = union(enum) {
    add_ptr: c_longlong,
    add_data: c_longlong,
    output,
    input,
    /// operations contained between '[' and ']'
    while_nonzero: []Operation,

    fn deinit(operation: *Operation, allocator: std.mem.Allocator) void {
        switch (operation.*) {
            .while_nonzero => |operations| {
                deinitList(operations, allocator);
                allocator.free(operations);
            },
            else => {},
        }
    }

    fn deinitList(operations: []Operation, allocator: std.mem.Allocator) void {
        for (operations) |*op| {
            op.deinit(allocator);
        }
    }
};

pub const Parser = struct {
    operations: []Operation,

    fn parseJumpIfZero(tokens: anytype, allocator: std.mem.Allocator) ![]Operation {
        var operations: std.ArrayList(Operation) = try .initCapacity(allocator, 0);
        errdefer {
            Operation.deinitList(operations.items, allocator);
            operations.deinit(allocator);
        }

        while (tokens.next()) |token| {
            switch (@as(Token, token)) {
                .increment_ptr => try operations.append(allocator, .{ .add_ptr = 1 }),
                .decrement_ptr => try operations.append(allocator, .{ .add_ptr = -1 }),
                .increment_data => try operations.append(allocator, .{ .add_data = 1 }),
                .decrement_data => try operations.append(allocator, .{ .add_data = -1 }),
                .output => try operations.append(allocator, .output),
                .input => try operations.append(allocator, .input),
                .jump_if_zero => try operations.append(allocator, .{
                    .while_nonzero = try parseJumpIfZero(tokens, allocator),
                }),
                .jump_if_nonzero => return operations.toOwnedSlice(allocator),
            }
        }

        return error.UnexpectedEof;
    }

    pub fn parse(tokens: anytype, allocator: std.mem.Allocator) !Parser {
        var operations: std.ArrayList(Operation) = try .initCapacity(allocator, 0);
        errdefer {
            Operation.deinitList(operations.items, allocator);
            operations.deinit(allocator);
        }

        while (tokens.next()) |token| {
            switch (@as(Token, token)) {
                .increment_ptr => try operations.append(allocator, .{ .add_ptr = 1 }),
                .decrement_ptr => try operations.append(allocator, .{ .add_ptr = -1 }),
                .increment_data => try operations.append(allocator, .{ .add_data = 1 }),
                .decrement_data => try operations.append(allocator, .{ .add_data = -1 }),
                .output => try operations.append(allocator, .output),
                .input => try operations.append(allocator, .input),
                .jump_if_zero => try operations.append(allocator, .{
                    .while_nonzero = try parseJumpIfZero(tokens, allocator),
                }),
                .jump_if_nonzero => return error.UnexpectedNonzeroJump,
            }
        }

        return .{ .operations = try operations.toOwnedSlice(allocator) };
    }

    pub fn deinit(parser: *Parser, allocator: std.mem.Allocator) void {
        Operation.deinitList(parser.operations, allocator);
        allocator.free(parser.operations);
    }
};

test Parser {
    var tok = tokenizer.Tokenizer.init("++-><[.],");
    var parser = try Parser.parse(&tok, std.testing.allocator);
    defer parser.deinit(std.testing.allocator);

    var inner = [_]Operation{.output};
    try std.testing.expectEqualDeep(&[_]Operation{
        .{ .add_data = 1 },
        .{ .add_data = 1 },
        .{ .add_data = -1 },
        .{ .add_ptr = 1 },
        .{ .add_ptr = -1 },
        .{ .while_nonzero = &inner },
        .input,
    }, parser.operations);
}
