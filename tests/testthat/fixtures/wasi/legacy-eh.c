// wasi-sdk: -mllvm -wasm-enable-sjlj -mexception-handling -lsetjmp
/* setjmp/longjmp compiled with the legacy exception-handling encoding
   (wasi-sdk's default), which toywasm doesn't implement: loading it must
   fail cleanly. */
#include <setjmp.h>
#include <stdio.h>

static jmp_buf env;

int main(void) {
    if (setjmp(env) == 0) longjmp(env, 1);
    printf("jumped\n");
    return 0;
}
