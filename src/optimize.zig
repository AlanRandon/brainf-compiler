const std = @import("std");
const Operation = @import("parser.zig").Operation;

pub fn collapseConsecutiveAddPass(operations: *std.ArrayList(Operation), allocator: std.mem.Allocator) !void {
    var result: std.ArrayList(Operation) = .init(allocator);
    errdefer result.deinit();

    for (operations.items) |*operation| {
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
                try result.append(.{ .while_nonzero = inner_ops });
                continue;
            },
            else => {},
        }

        try result.append(operation.*);
    }

    operations.deinit();
    operations.* = result;
}

test collapseConsecutiveAddPass {
    var operations: std.ArrayList(Operation) = .init(std.testing.allocator);
    defer operations.deinit();

    try operations.appendSlice(
        &.{
            .{ .add_data = 1 },
            .{ .add_data = 1 },
            .{ .add_data = 1 },
        },
    );

    try collapseConsecutiveAddPass(&operations, std.testing.allocator);

    try std.testing.expectEqualDeep(&[_]Operation{
        .{ .add_data = 3 },
    }, operations.items);
}

test "collapseConsecutiveAddPass is recursive" {
    var tok = @import("tokenizer.zig").Tokenizer.init("[.++.+.]");
    var parser = try @import("parser.zig").Parser.parse(&tok, std.testing.allocator);
    defer parser.deinit();

    var inner_operations: std.ArrayList(Operation) = .init(std.testing.allocator);
    defer inner_operations.deinit();

    try inner_operations.appendSlice(&.{
        .output,
        .{ .add_data = 2 },
        .output,
        .{ .add_data = 1 },
        .output,
    });

    try collapseConsecutiveAddPass(&parser.operations, std.testing.allocator);

    try std.testing.expectEqualDeep(
        &[_]Operation{.{ .while_nonzero = inner_operations }},
        parser.operations.items,
    );
}
