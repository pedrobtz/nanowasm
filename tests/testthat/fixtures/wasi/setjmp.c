// wasi-sdk: -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false -mexception-handling -lsetjmp
/* setjmp/longjmp, which wasi-sdk implements with WebAssembly exception
   handling: jumps out of nested calls, longjmp(env, 0), and a jump buffer
   reused after a jump. */
#include <setjmp.h>
#include <stdio.h>

static jmp_buf env;

static void deep(int depth, int code) {
    if (depth == 0) longjmp(env, code);
    deep(depth - 1, code);
}

int main(void) {
    int r = setjmp(env);
    if (r == 0) {
        printf("first pass\n");
        deep(10, 42);
    }
    printf("longjmp returned %d\n", r);
    if (r == 42) {
        r = setjmp(env);
        if (r == 0) deep(3, 0);
        printf("longjmp(env, 0) returned %d\n", r);
    }
    return 0;
}
