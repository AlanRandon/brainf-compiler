const std = @import("std");
const c = @import("c.zig");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const translator = @import("translator.zig");

test {
    std.testing.refAllDecls(tokenizer);
    std.testing.refAllDecls(parser);
    std.testing.refAllDecls(translator);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var tok = tokenizer.Tokenizer.init(@embedFile("main.bf"));
    var p = try parser.Parser.parse(&tok, allocator);
    defer p.deinit();

    // TODO: opt

    var trns = try translator.Translator.init();
    defer trns.deinit();

    trns.translateProgram(p.operations.items);

    var err: [*c]u8 = null;
    // TODO: verify
    _ = c.LLVMVerifyModule(trns.module, c.LLVMAbortProcessAction, &err);
    c.LLVMDisposeMessage(err);

    // TODO: output obj

    if (c.LLVMWriteBitcodeToFile(trns.module, "out.bc") != 0) {
        return error.EmitBytecode;
    }
}
