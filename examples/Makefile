.PHONY: clean

EXAMPLE=hello

BFC=../zig-out/bin/bfc
BF_RUNTIME=../zig-out/bin/brainf.o

main: out.o
	ld out.o ${BF_RUNTIME} -o main

out.o: ${INPUT}
	${BFC} ${EXAMPLE}.bf

out.bc: ${EXAMPLE}.bf
	${BFC} ${EXAMPLE}.bf -f bitcode

out.ll: ${EXAMPLE}.bf
	${BFC} ${EXAMPLE}.bf -f ir_text -O0

clean:
	$(RM) main out.o out.bc out.ll
