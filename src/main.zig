const std = @import("std");
const clap = @import("clap");
const c = @import("c.zig");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const translator = @import("translator.zig");
const optimize = @import("optimize.zig");

test {
    std.testing.refAllDecls(tokenizer);
    std.testing.refAllDecls(parser);
    std.testing.refAllDecls(optimize);
    std.testing.refAllDecls(translator);
}

const args_definition =
    \\-h, --help Display this help and exit.
    \\-o, --output <FILE> Place the output into <FILE>.
    \\-f, --format <FORMAT> The format of the output. (bitcode|object|ir_text, default: object)
    \\-t, --target <TRIPLE> The LLVM target triple to use. (default: 
++ c.LLVM_DEFAULT_TARGET_TRIPLE ++
    \\)
    \\--cpu <CPU> The specific CPU model to target.
    \\--cpu-features <FEATURES> The specific CPU features to target.
    \\-O, --optimize <OPTLEVEL> The level of optimization to use with LLVM.
    \\<FILE> The source file to translate.
    \\
;

fn printUsage(stream: anytype, params: anytype) !void {
    try stream.writeAll("USAGE: ");
    try clap.usage(stream, clap.Help, params);
    try stream.writeAll("\n");
}

const ZeroTerminatedString = union(enum) {
    constant: [:0]const u8,
    allocated: struct {
        ptr: [:0]const u8,
        allocator: std.mem.Allocator,
    },

    pub fn allocZ(str: []const u8, allocator: std.mem.Allocator) !ZeroTerminatedString {
        const result = try allocator.allocSentinel(u8, str.len, 0);
        @memcpy(result[0..str.len], str);
        return .{ .allocated = .{ .ptr = result, .allocator = allocator } };
    }

    pub fn fromConst(str: [:0]const u8) ZeroTerminatedString {
        return .{ .constant = str };
    }

    pub fn fromC(str: [*c]const u8) ZeroTerminatedString {
        var len: usize = 0;
        while (str[len] != 0) {
            len += 1;
        }

        return .{ .constant = @ptrCast(str[0..len]) };
    }

    pub fn value(str: *const ZeroTerminatedString) [:0]const u8 {
        return switch (str.*) {
            .constant => |s| s,
            .allocated => |s| s.ptr,
        };
    }

    pub fn deinit(str: *const ZeroTerminatedString) void {
        switch (str.*) {
            .constant => {},
            .allocated => |s| {
                s.allocator.free(s.ptr);
            },
        }
    }
};

const OutputFormat = enum {
    object,
    bitcode,
    ir_text,
};

const max_source_size = 5 * 1024 * 1024; // 5 MiB

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(args_definition);

    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, .{
        .FILE = clap.parsers.string,
        .FORMAT = clap.parsers.enumeration(OutputFormat),
        .TRIPLE = clap.parsers.string,
        .CPU = clap.parsers.string,
        .FEATURES = clap.parsers.string,
        .OPTLEVEL = clap.parsers.string,
    }, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        const stderr = std.io.getStdErr().writer();
        try printUsage(stderr, &params);
        try diag.report(stderr, err);
        return err;
    };
    defer args.deinit();

    if (args.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    const source_path = args.positionals[0] orelse return error.MissingInputFile;
    const output_format = if (args.args.format) |format| format else .object;

    const source_buf = if (std.mem.eql(u8, source_path, "-"))
        try std.io.getStdIn().readToEndAlloc(allocator, max_source_size)
    else
        try std.fs.cwd().readFileAlloc(allocator, source_path, max_source_size);
    defer allocator.free(source_buf);

    var tok = tokenizer.Tokenizer.init(source_buf);
    var p = try parser.Parser.parse(&tok, allocator);
    defer p.deinit();

    try optimize.collapseConsecutiveAddPass(&p.operations, allocator);

    var trns = try translator.Translator.init();
    defer trns.deinit();

    trns.translateProgram(p.operations.items);

    c.LLVMInitializeAllTargetInfos();
    c.LLVMInitializeAllTargets();
    c.LLVMInitializeAllTargetMCs();
    c.LLVMInitializeAllAsmParsers();
    c.LLVMInitializeAllAsmPrinters();

    const triple = if (args.args.target) |triple|
        try ZeroTerminatedString.allocZ(triple, allocator)
    else
        ZeroTerminatedString.fromConst(c.LLVM_DEFAULT_TARGET_TRIPLE);
    defer triple.deinit();

    const cpu_name = if (args.args.cpu) |cpu|
        try ZeroTerminatedString.allocZ(cpu, allocator)
    else if (std.mem.eql(u8, triple.value(), c.LLVM_DEFAULT_TARGET_TRIPLE))
        ZeroTerminatedString.fromC(c.LLVMGetHostCPUName())
    else
        ZeroTerminatedString.fromConst("generic");
    defer cpu_name.deinit();

    const cpu_features = if (args.args.@"cpu-features") |features|
        try ZeroTerminatedString.allocZ(features, allocator)
    else if (std.mem.eql(u8, triple.value(), c.LLVM_DEFAULT_TARGET_TRIPLE))
        ZeroTerminatedString.fromC(c.LLVMGetHostCPUFeatures())
    else
        ZeroTerminatedString.fromConst("");
    defer cpu_features.deinit();

    var err: [*c]u8 = null;
    var target_ref: c.LLVMTargetRef = undefined;
    if (c.LLVMGetTargetFromTriple(triple.value(), &target_ref, &err) != 0) {
        defer c.LLVMDisposeMessage(err);
        std.log.err("Failed to get target error: {s}\n", .{err});
        return error.GetTarget;
    }

    const target_machine = c.LLVMCreateTargetMachine(
        target_ref,
        triple.value(),
        cpu_name.value(),
        cpu_features.value(),
        c.LLVMCodeGenLevelAggressive,
        c.LLVMRelocDefault,
        c.LLVMCodeModelDefault,
    ) orelse return error.GetTargetMachine;
    defer c.LLVMDisposeTargetMachine(target_machine);

    const options = c.LLVMCreatePassBuilderOptions();
    defer c.LLVMDisposePassBuilderOptions(options);

    const passes = try std.fmt.allocPrintZ(allocator, "default<O{s}>", .{
        if (args.args.optimize) |opt| opt else "3",
    });
    defer allocator.free(passes);

    if (c.LLVMRunPasses(trns.module, passes, target_machine, options)) |opt_err| {
        const message = c.LLVMGetErrorMessage(opt_err);
        defer c.LLVMDisposeMessage(message);

        std.log.err("Failed to optimize module: {s}\n", .{message});

        return error.LlvmOpt;
    }

    const output_path = if (args.args.output) |output| try ZeroTerminatedString.allocZ(output, allocator) else null;
    defer if (output_path) |output| output.deinit();

    switch (output_format) {
        .object => {
            const path = if (output_path) |o| o.value() else "out.o";
            if (c.LLVMTargetMachineEmitToFile(target_machine, trns.module, path, c.LLVMObjectFile, &err) != 0) {
                defer c.LLVMDisposeMessage(err);
                std.log.err("Failed to emit object: {s}\n", .{err});
                return error.EmitObject;
            }
        },
        .bitcode => {
            const path = if (output_path) |o| o.value() else "out.bc";
            if (c.LLVMWriteBitcodeToFile(trns.module, path) != 0) {
                return error.EmitBytecode;
            }
        },
        .ir_text => {
            const path = if (output_path) |o| o.value() else "out.ll";
            if (c.LLVMPrintModuleToFile(trns.module, path, &err) != 0) {
                defer c.LLVMDisposeMessage(err);
                std.log.err("Failed to print module: {s}\n", .{err});
                return error.EmitIrText;
            }
        },
    }
}
