/*
 * libFuzzer target: decode, validate and instantiate a module with the
 * vendored toywasm, configured as nanowasm builds it.
 *
 * Run by .github/workflows/fuzz.yml through pedrobtz/r-actions, compiled
 * without R from the C files in src/toywasm/ and src/toywasm_shim.c, with
 * -Isrc -Isrc/toywasm. NANOWASM_REAL_ASSERT turns toywasm's assertions back on
 * (the R build compiles them out), so a broken invariant is a finding too.
 *
 * Start functions are not run: arbitrary code may loop forever, and the
 * interpreter loop is exercised by the package's tests. Everything else
 * that instantiation does (allocating memories and tables, evaluating
 * constant expressions, copying data and element segments) is.
 *
 * Build with -DNANOWASM_FUZZ_MAIN for a replay driver that runs the target
 * on each file named on the command line, for platforms without libFuzzer.
 */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "toywasm/exec_context.h"
#include "toywasm/instance.h"
#include "toywasm/load_context.h"
#include "toywasm/mem.h"
#include "toywasm/module.h"
#include "toywasm/report.h"
#include "toywasm/type.h"

/* Enough for real modules, small enough that a huge declared table or
   memory is refused instead of exhausting the fuzzer. */
#define FUZZ_MEMORY_LIMIT (64 * 1024 * 1024)

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
        struct mem_context mctx;
        mem_context_init(&mctx);
        if (mem_context_setlimit(&mctx, FUZZ_MEMORY_LIMIT) != 0) {
                return 0;
        }

        struct load_context lctx;
        load_context_init(&lctx, &mctx);
        struct module *m = NULL;
        int ret = module_create(&m, data, data + size, &lctx);
        (void)report_getmessage(&lctx.report);
        load_context_clear(&lctx);
        if (ret != 0) {
                mem_context_clear(&mctx);
                return 0;
        }

        /* nanowasm only instantiates modules whose imports it can satisfy;
           without imports, that is modules with none. */
        if (m->nimports == 0) {
                struct mem_context imctx;
                mem_context_init(&imctx);
                if (mem_context_setlimit(&imctx, FUZZ_MEMORY_LIMIT) == 0) {
                        struct instance *inst = NULL;
                        struct report report;
                        report_init(&report);
                        ret = instance_create_no_init(&imctx, m, &inst, NULL,
                                                      &report);
                        report_clear(&report);
                        if (ret == 0) {
                                if (!m->has_start) {
                                        struct exec_context ctx;
                                        exec_context_init(&ctx, inst, &imctx);
                                        ctx.options.max_frames = 1000;
                                        ctx.options.max_stackcells = 100000;
                                        ret = instance_execute_init(&ctx);
                                        while (IS_RESTARTABLE(ret)) {
                                                ret = instance_execute_handle_restart_once(
                                                        &ctx, ret);
                                        }
                                        exec_context_clear(&ctx);
                                }
                                instance_destroy(inst);
                        }
                }
                mem_context_clear(&imctx);
        }
        module_destroy(&mctx, m);
        mem_context_clear(&mctx);
        return 0;
}

#if defined(NANOWASM_FUZZ_MAIN)
int
main(int argc, char **argv)
{
        for (int i = 1; i < argc; i++) {
                FILE *fp = fopen(argv[i], "rb");
                if (fp == NULL) {
                        perror(argv[i]);
                        return 1;
                }
                fseek(fp, 0, SEEK_END);
                long n = ftell(fp);
                fseek(fp, 0, SEEK_SET);
                uint8_t *buf = malloc(n > 0 ? (size_t)n : 1);
                if (buf == NULL || fread(buf, 1, (size_t)n, fp) != (size_t)n) {
                        fprintf(stderr, "%s: read failed\n", argv[i]);
                        return 1;
                }
                fclose(fp);
                LLVMFuzzerTestOneInput(buf, (size_t)n);
                free(buf);
                printf("ok %s\n", argv[i]);
        }
        return 0;
}
#endif
