const std = @import("std");

pub const Token = union(enum) {
    /// >
    increment_ptr,
    /// <
    decrement_ptr,
    /// +
    increment_data,
    /// -
    decrement_data,
    /// .
    output,
    /// ,
    input,
    /// [
    jump_if_zero,
    /// ]
    jump_if_nonzero,
};

pub const Tokenizer = struct {
    input: []const u8,
    position: usize,

    pub fn init(input: []const u8) Tokenizer {
        return .{ .input = input, .position = 0 };
    }

    pub fn next(tokenizer: *Tokenizer) ?Token {
        if (tokenizer.position >= tokenizer.input.len) {
            return null;
        }

        const ch = tokenizer.input[tokenizer.position];
        const token: Token = switch (ch) {
            '>' => .increment_ptr,
            '<' => .decrement_ptr,
            '+' => .increment_data,
            '-' => .decrement_data,
            '.' => .output,
            ',' => .input,
            '[' => .jump_if_zero,
            ']' => .jump_if_nonzero,
            else => {
                tokenizer.position += 1;
                return tokenizer.next();
            },
        };

        tokenizer.position += 1;
        return token;
    }
};

test Tokenizer {
    var tokenizer: Tokenizer = .init("[++]+");

    try std.testing.expectEqual(.jump_if_zero, tokenizer.next());
    try std.testing.expectEqual(.increment_data, tokenizer.next());
    try std.testing.expectEqual(.increment_data, tokenizer.next());
    try std.testing.expectEqual(.jump_if_nonzero, tokenizer.next());
    try std.testing.expectEqual(.increment_data, tokenizer.next());
    try std.testing.expectEqual(null, tokenizer.next());
}
