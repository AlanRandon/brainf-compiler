const std = @import("std");

const Context = struct {
    stdin: std.fs.File,
    stdout: std.fs.File,
};

extern fn brainf_main(context: *Context) void;

pub export fn brainf_output(context: *Context, value: u8) callconv(.c) void {
    // var i = value;
    // if (i == 0) {
    //     _ = context.stdout.writeAll("0\n") catch {};
    //     return;
    // }

    // while (i != 0) {
    //     _ = context.stdout.writeAll(&.{i % 10 + '0'}) catch {};
    //     i /= 10;
    // }
    // _ = context.stdout.writeAll(&.{'\n'}) catch {};
    _ = context.stdout.writeAll(&.{value}) catch {};
}

pub export fn brainf_input(context: *Context) callconv(.c) u8 {
    var buf: [1]u8 = undefined;
    const len = context.stdin.read(&buf) catch return 0;
    if (len == 1) {
        return buf[0];
    }

    return 0;
}

comptime {
    if (!@import("builtin").is_test) {
        @export(&_start, .{ .name = "_start" });
    }
}

pub fn main() !void {
    var context: Context = .{
        .stdin = std.io.getStdIn(),
        .stdout = std.io.getStdIn(),
    };

    if (std.posix.isatty(context.stdin.handle)) {
        const fd = context.stdin.handle;
        const prev_termios = try std.posix.tcgetattr(fd);
        defer std.posix.tcsetattr(fd, .FLUSH, prev_termios) catch {};

        var termios = prev_termios;
        termios.lflag.ECHO = false; // disable echo input
        termios.lflag.ECHONL = false; // disable echo newlines
        termios.lflag.ICANON = false; // disable canonical mode (don't wait for line terminator, disable line editing)
        termios.lflag.IEXTEN = false; // disable implemenation-defined input processing
        try std.posix.tcsetattr(fd, .FLUSH, termios);

        brainf_main(&context);
    } else {
        brainf_main(&context);
    }
}

pub fn _start() callconv(.c) noreturn {
    std.process.exit(std.start.callMain());
}
