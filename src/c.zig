pub const c = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/BitWriter.h");
    @cInclude("llvm-c/Analysis.h");
    @cInclude("llvm-c/Target.h");
    @cInclude("llvm-c/TargetMachine.h");
    @cInclude("llvm-c/Transforms/PassBuilder.h");
});
