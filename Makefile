.PHONY: clean

main: out.o zig-out/bin/brainf.o
	ld out.o zig-out/bin/brainf.o -lc -o main

out.bc:
	zig build run

zig-out/bin/brainf.o:
	zig build run

out.o: out.bc
	llc --filetype=obj out.bc

out.ll: out.bc
	llvm-dis out.bc

clean:
	$(RM) main out.o out.bc out.ll
