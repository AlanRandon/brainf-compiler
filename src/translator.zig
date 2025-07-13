const std = @import("std");
const c = @import("c.zig");
const Operation = @import("parser.zig").Operation;

const cell_count = 30_000;

const Types = struct {
    ptr: c.LLVMTypeRef,
    cells: c.LLVMTypeRef,
    byte: c.LLVMTypeRef,
    int32: c.LLVMTypeRef,
    /// void main(void *user_context)
    entry_signature: c.LLVMTypeRef,
    /// int8_t input(void *user_context)
    input_signature: c.LLVMTypeRef,
    /// void output(void *user_context, int8_t data)
    output_signature: c.LLVMTypeRef,

    fn init() Types {
        const byte = c.LLVMInt8Type();
        const int32 = c.LLVMInt32Type();
        const ptr = c.LLVMPointerType(byte, 0);
        const cells = c.LLVMArrayType(byte, cell_count);
        const void_type = c.LLVMVoidType();

        const params = [_]c.LLVMTypeRef{ptr};
        const entry_signature = c.LLVMFunctionType(void_type, @constCast(&params), params.len, 0);
        const input_signature = c.LLVMFunctionType(byte, @constCast(&params), params.len, 0);

        const output_params = [_]c.LLVMTypeRef{ ptr, byte };
        const output_signature = c.LLVMFunctionType(void_type, @constCast(&output_params), output_params.len, 0);

        return .{
            .ptr = ptr,
            .cells = cells,
            .int32 = int32,
            .byte = byte,
            .entry_signature = entry_signature,
            .input_signature = input_signature,
            .output_signature = output_signature,
        };
    }
};

pub const Translator = struct {
    module: c.LLVMModuleRef,
    builder: c.LLVMBuilderRef,
    entry_function: c.LLVMValueRef,
    input_function: c.LLVMValueRef,
    output_function: c.LLVMValueRef,
    cell_ptr_ptr: c.LLVMValueRef,
    types: Types,

    current_cell_ptr: ?c.LLVMValueRef = null,
    current_data: ?c.LLVMValueRef = null,

    pub fn init() !Translator {
        const module = c.LLVMModuleCreateWithName("brainf-module");
        errdefer c.LLVMDisposeModule(module);

        const types = Types.init();

        const input_func = c.LLVMAddFunction(module, "brainf_input", types.input_signature);
        c.LLVMSetLinkage(input_func, c.LLVMExternalLinkage);

        const output_func = c.LLVMAddFunction(module, "brainf_output", types.output_signature);
        c.LLVMSetLinkage(output_func, c.LLVMExternalLinkage);

        const entry_func = c.LLVMAddFunction(module, "brainf_main", types.entry_signature);
        const entry = c.LLVMAppendBasicBlock(entry_func, "entry");

        const builder = c.LLVMCreateBuilder();
        errdefer c.LLVMDisposeBuilder(builder);

        c.LLVMPositionBuilderAtEnd(builder, entry);

        const cell_start_ptr = c.LLVMBuildAlloca(builder, types.cells, "start_cell_ptr");
        _ = c.LLVMBuildMemSet(
            builder,
            cell_start_ptr,
            c.LLVMConstInt(types.byte, 0, 0),
            c.LLVMConstInt(types.int32, cell_count, 0),
            0,
        );

        const cell_ptr_ptr = c.LLVMBuildAlloca(builder, types.ptr, "cell_ptr_ptr");
        _ = c.LLVMBuildStore(builder, cell_start_ptr, cell_ptr_ptr);

        return .{
            .module = module,
            .builder = builder,
            .entry_function = entry_func,
            .input_function = input_func,
            .output_function = output_func,
            .cell_ptr_ptr = cell_ptr_ptr,
            .types = types,
        };
    }

    pub fn deinit(translator: *Translator) void {
        c.LLVMDisposeBuilder(translator.builder);
        c.LLVMDisposeModule(translator.module);
    }

    pub fn getCellPtr(translator: *Translator) c.LLVMValueRef {
        if (translator.current_cell_ptr) |ptr| {
            return ptr;
        }

        const ptr = c.LLVMBuildLoad2(translator.builder, translator.types.ptr, translator.cell_ptr_ptr, "cell_ptr");
        translator.current_cell_ptr = ptr;
        return ptr;
    }

    pub fn getCellData(translator: *Translator) c.LLVMValueRef {
        if (translator.current_data) |data| {
            return data;
        }

        const data = c.LLVMBuildLoad2(translator.builder, translator.types.byte, translator.getCellPtr(), "data");
        translator.current_data = data;
        return data;
    }

    fn translateOperation(translator: *Translator, operation: Operation) void {
        switch (operation) {
            .add_data => |value| {
                const add_result = c.LLVMBuildAdd(translator.builder, translator.getCellData(), c.LLVMConstInt(translator.types.byte, @bitCast(value), 0), "new_data");
                _ = c.LLVMBuildStore(translator.builder, add_result, translator.getCellPtr());
                translator.current_data = add_result;
            },
            .add_ptr => |value| {
                const offsets = [_]c.LLVMValueRef{c.LLVMConstInt(translator.types.int32, @bitCast(value), 0)};
                const new_cell_ptr = c.LLVMBuildGEP2(translator.builder, translator.types.ptr, translator.getCellPtr(), @constCast(&offsets), offsets.len, "new_cell_ptr");
                _ = c.LLVMBuildStore(translator.builder, new_cell_ptr, translator.cell_ptr_ptr);
                translator.current_cell_ptr = null;
                translator.current_data = null;
            },
            .output => {
                const args = [_]c.LLVMValueRef{ c.LLVMGetParam(translator.entry_function, 0), translator.getCellData() };
                _ = c.LLVMBuildCall2(translator.builder, translator.types.output_signature, translator.output_function, @constCast(&args), args.len, "");
            },
            .input => {
                const args = [_]c.LLVMValueRef{c.LLVMGetParam(translator.entry_function, 0)};
                const data = c.LLVMBuildCall2(translator.builder, translator.types.input_signature, translator.input_function, @constCast(&args), args.len, "data");
                _ = c.LLVMBuildStore(translator.builder, data, translator.getCellPtr());
                translator.current_data = data;
            },
            .while_nonzero => |loop_body| {
                const loop_cond = c.LLVMAppendBasicBlock(translator.entry_function, "nonzero_loop_cond");
                const loop = c.LLVMAppendBasicBlock(translator.entry_function, "nonzero_loop");
                const loop_end = c.LLVMAppendBasicBlock(translator.entry_function, "nonzero_loop_end");

                _ = c.LLVMBuildBr(translator.builder, loop_cond);
                c.LLVMPositionBuilderAtEnd(translator.builder, loop_cond);

                // the current cell ptr or data may change in the loop body
                translator.current_cell_ptr = null;
                translator.current_data = null;

                const data_is_zero = c.LLVMBuildICmp(translator.builder, c.LLVMIntEQ, translator.getCellData(), c.LLVMConstInt(translator.types.byte, 0, 0), "data_is_zero");
                _ = c.LLVMBuildCondBr(translator.builder, data_is_zero, loop_end, loop);

                c.LLVMPositionBuilderAtEnd(translator.builder, loop);
                translator.translateMany(loop_body.items);
                _ = c.LLVMBuildBr(translator.builder, loop_cond);

                translator.current_cell_ptr = null;
                translator.current_data = null;

                c.LLVMPositionBuilderAtEnd(translator.builder, loop_end);
            },
        }
    }

    fn translateMany(translator: *Translator, operations: []Operation) void {
        for (operations) |operation| {
            translator.translateOperation(operation);
        }
    }

    pub fn translateProgram(translator: *Translator, operations: []Operation) void {
        translator.translateMany(operations);
        _ = c.LLVMBuildRetVoid(translator.builder);
    }
};
