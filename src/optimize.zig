const std = @import("std");
const Operation = @import("parser.zig").Operation;

pub fn collapseConsecutiveAddPass(operations: *[]Operation, allocator: std.mem.Allocator) !void {
    var result: std.ArrayList(Operation) = try .initCapacity(allocator, 0);
    errdefer result.deinit(allocator);

    for (operations.*) |*operation| {
        switch (operation.*) {
            .add_data => |value| if (result.items.len > 0) switch (result.items[result.items.len - 1]) {
                .add_data => |*old_value| {
                    old_value.* += value;
                    if (old_value.* == 0) {
                        _ = result.pop();
                    }
                    continue;
                },
                else => {},
            },
            .add_ptr => |value| if (result.items.len > 0) switch (result.items[result.items.len - 1]) {
                .add_ptr => |*old_value| {
                    old_value.* += value;
                    if (old_value.* == 0) {
                        _ = result.pop();
                    }
                    continue;
                },
                else => {},
            },
            .while_nonzero => |inner| {
                var inner_ops = inner;
                try collapseConsecutiveAddPass(&inner_ops, allocator);
                try result.append(allocator, .{ .while_nonzero = inner_ops });
                continue;
            },
            else => {},
        }

        try result.append(allocator, operation.*);
    }

    allocator.free(operations.*);
    operations.* = try result.toOwnedSlice(allocator);
}

fn testingAllocSlice(comptime T: type, slice: []const T) ![]T {
    const allocated_slice = try std.testing.allocator.alloc(T, slice.len);
    @memcpy(allocated_slice, slice);
    return allocated_slice;
}

test collapseConsecutiveAddPass {
    var operations = try testingAllocSlice(Operation, &.{
        .{ .add_data = 1 },
        .{ .add_data = 1 },
        .{ .add_data = 1 },
    });
    defer std.testing.allocator.free(operations);

    try collapseConsecutiveAddPass(&operations, std.testing.allocator);

    try std.testing.expectEqualDeep(&[_]Operation{
        .{ .add_data = 3 },
    }, operations);
}

test "collapseConsecutiveAddPass is recursive" {
    var tok = @import("tokenizer.zig").Tokenizer.init("[.++.+.]");
    var parser = try @import("parser.zig").Parser.parse(&tok, std.testing.allocator);
    defer parser.deinit(std.testing.allocator);

    const inner_operations = try testingAllocSlice(Operation, &.{
        .output,
        .{ .add_data = 2 },
        .output,
        .{ .add_data = 1 },
        .output,
    });
    defer std.testing.allocator.free(inner_operations);

    try collapseConsecutiveAddPass(&parser.operations, std.testing.allocator);

    try std.testing.expectEqualDeep(
        &[_]Operation{.{ .while_nonzero = inner_operations }},
        parser.operations,
    );
}
