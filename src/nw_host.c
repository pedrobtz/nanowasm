/*
 * R functions as WebAssembly imports.
 *
 * Every imported function gets a binding: a toywasm funcinst whose host
 * instance is the binding itself, so one C trampoline serves them all and
 * recovers the R function from the host_instance pointer it is given.
 *
 * The trampoline runs with toywasm's interpreter frames below it on the C
 * stack, so an R longjmp must never pass through it. Two layers ensure
 * that:
 *
 * 1. The R function is called through an R wrapper (see R/imports.R) that
 *    catches errors with tryCatch() and returns them as values.
 * 2. Everything else that can jump (an interrupt, a restart, running out of
 *    memory while converting values) is caught by R_UnwindProtect(), whose
 *    cleanup longjmps back into the trampoline. The trampoline makes the
 *    Wasm code trap, and once toywasm has unwound and its context is
 *    cleared, nw_finish_run() resumes the jump with R_ContinueUnwind().
 */
#include <errno.h>
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>

#include "nanowasm.h"

#include "toywasm/cell.h"
#include "toywasm/instance.h"

static SEXP nw_unwind_token = NULL;

void
nw_host_init(void)
{
        nw_unwind_token = R_MakeUnwindCont();
        R_PreserveObject(nw_unwind_token);
}

struct host_call {
        struct nw_host_binding *b;
        const struct functype *ft;
        const struct cell *params;
        struct cell *results;
        bool ok;
};

/* "env.log", for messages. */
static void
import_label(const struct import *im, char *buf, size_t n)
{
        snprintf(buf, n, "%.*s.%.*s", (int)im->module_name.nbytes,
                 im->module_name.data, (int)im->name.nbytes, im->name.data);
}

/* Record why the call failed. Runs inside R_UnwindProtect. */
static void
set_failure(struct nw_instance *ni, SEXP failure)
{
        PROTECT(failure);
        if (ni->host_failure == NULL) {
                R_PreserveObject(failure);
                ni->host_failure = failure;
        }
        UNPROTECT(1);
}

/* The body of a host call: convert, call R, convert back. Everything that
   can allocate or jump happens here, under R_UnwindProtect. */
static SEXP
host_body(void *data)
{
        struct host_call *hc = data;
        struct nw_host_binding *b = hc->b;
        struct nw_instance *ni = b->owner;
        const struct resulttype *pt = &hc->ft->parameter;
        const struct resulttype *rt = &hc->ft->result;
        char label[256];
        import_label(b->im, label, sizeof(label));

        struct val *vals =
                (struct val *)R_alloc(pt->ntypes + 1, sizeof(struct val));
        vals_from_cells(vals, hc->params, pt);
        const bool lossy = Rf_getAttrib(b->fn, Rf_install("nanowasm_lossy_i64")) !=
                           R_NilValue;
        SEXP args = PROTECT(Rf_allocVector(VECSXP, pt->ntypes));
        for (uint32_t i = 0; i < pt->ntypes; i++) {
                SEXP v = nw_val_to_sexp(&vals[i], pt->types[i]);
                if (v == NULL && lossy) {
                        v = Rf_ScalarReal((double)(int64_t)vals[i].u.i64);
                }
                if (v == NULL) {
                        char msg[512];
                        snprintf(msg, sizeof(msg),
                                 "Argument %u of the R function imported as "
                                 "`%s` (i64) is %lld, which a double cannot "
                                 "represent exactly.",
                                 (unsigned)(i + 1), label,
                                 (long long)(int64_t)vals[i].u.i64);
                        set_failure(ni, nw_fail2("nanowasm_precision_error",
                                                 "nanowasm_host_error", msg));
                        UNPROTECT(1);
                        return R_NilValue;
                }
                SET_VECTOR_ELT(args, i, v);
        }

        /* wrapper(args, self) returns list(TRUE, value) or
           list(FALSE, condition, message). */
        SEXP call = PROTECT(Rf_lang3(b->fn, args, ni->self));
        SEXP res = PROTECT(Rf_eval(call, R_GlobalEnv));
        if (!Rf_asLogical(VECTOR_ELT(res, 0))) {
                const char *msg = CHAR(STRING_ELT(VECTOR_ELT(res, 2), 0));
                SEXP failure = PROTECT(nw_fail("nanowasm_host_error", msg));
                SEXP fields = PROTECT(Rf_allocVector(VECSXP, 1));
                SET_VECTOR_ELT(fields, 0, VECTOR_ELT(res, 1));
                Rf_setAttrib(fields, R_NamesSymbol, Rf_mkString("parent"));
                SET_VECTOR_ELT(failure, 2, fields);
                set_failure(ni, failure);
                UNPROTECT(5);
                return R_NilValue;
        }

        SEXP value = VECTOR_ELT(res, 1);
        struct val *out =
                (struct val *)R_alloc(rt->ntypes + 1, sizeof(struct val));
        if (rt->ntypes > 1 &&
            (TYPEOF(value) != VECSXP || XLENGTH(value) != rt->ntypes)) {
                char msg[512];
                snprintf(msg, sizeof(msg),
                         "The R function imported as `%s` must return a list "
                         "of %u values.",
                         label, (unsigned)rt->ntypes);
                set_failure(ni, nw_fail("nanowasm_host_error", msg));
                UNPROTECT(3);
                return R_NilValue;
        }
        for (uint32_t i = 0; i < rt->ntypes; i++) {
                SEXP v = rt->ntypes == 1 ? value : VECTOR_ELT(value, i);
                SEXP fail = nw_arg_to_val(v, rt->types[i], label,
                                          NW_ARG_RESULT - (R_xlen_t)i, &out[i]);
                if (fail != R_NilValue) {
                        PROTECT(fail);
                        SET_VECTOR_ELT(fail, 0,
                                       Rf_mkString("nanowasm_host_error"));
                        set_failure(ni, fail);
                        UNPROTECT(4);
                        return R_NilValue;
                }
        }
        vals_to_cells(out, hc->results, rt);
        hc->ok = true;
        UNPROTECT(3);
        return R_NilValue;
}

static void
host_cleanup(void *jbuf, Rboolean jump)
{
        if (jump) {
                longjmp(*(jmp_buf *)jbuf, 1);
        }
}

static int
host_trampoline(struct exec_context *ctx, struct host_instance *hi,
                const struct functype *ft, const struct cell *params,
                struct cell *results)
{
        /* hi is the first member of its binding. */
        struct nw_host_binding *b = (struct nw_host_binding *)(void *)hi;
        struct nw_instance *ni = b->owner;
        struct host_call hc = {b, ft, params, results, false};
        jmp_buf jbuf;
        if (setjmp(jbuf) != 0) {
                /* R is unwinding past this call: let toywasm unwind first. */
                ni->unwinding = true;
                return trap_with_id(ctx, TRAP_MISC,
                                    "R unwound through a host function");
        }
        R_UnwindProtect(host_body, &hc, host_cleanup, &jbuf, nw_unwind_token);
        if (!hc.ok) {
                return trap_with_id(ctx, TRAP_MISC, "host function failed");
        }
        return 0;
}

/*
 * Build the import object for a module whose imports are all functions,
 * one binding per import, with funcs[i] the R wrapper for import i.
 */
int
nw_host_bind(struct nw_instance *ni, SEXP funcs)
{
        const struct module *m = ni->mod->module;
        uint32_t n = m->nimports;
        if (n == 0) {
                return 0;
        }
        ni->bindings = calloc(n, sizeof(*ni->bindings));
        if (ni->bindings == NULL) {
                return ENOMEM;
        }
        ni->nbindings = n;
        int ret = import_object_alloc(&ni->mctx, n, &ni->imports);
        if (ret != 0) {
                return ret;
        }
        for (uint32_t i = 0; i < n; i++) {
                const struct import *im = &m->imports[i];
                struct nw_host_binding *b = &ni->bindings[i];
                b->hi.memory = NULL;
                b->hi.func_table = NULL;
                b->fn = VECTOR_ELT(funcs, i);
                b->im = im;
                b->owner = ni;
                b->fi.is_host = true;
                b->fi.u.host.instance = &b->hi;
                b->fi.u.host.type = &m->types[im->desc.u.typeidx];
                b->fi.u.host.func = host_trampoline;
                struct import_object_entry *e = &ni->imports->entries[i];
                e->module_name = &im->module_name;
                e->name = &im->name;
                e->type = EXTERNTYPE_FUNC;
                e->u.func = &b->fi;
        }
        return 0;
}

void
nw_host_release(struct nw_instance *ni)
{
        if (ni->imports != NULL) {
                import_object_destroy(&ni->mctx, ni->imports);
                ni->imports = NULL;
        }
        free(ni->bindings);
        ni->bindings = NULL;
        if (ni->host_failure != NULL) {
                R_ReleaseObject(ni->host_failure);
                ni->host_failure = NULL;
        }
}

/*
 * After a run, once the exec context is cleared: resume an R unwind that a
 * host call interrupted (this does not return), or hand back the failure a
 * host call recorded. Returns NULL if neither happened.
 */
SEXP
nw_finish_run(struct nw_instance *ni)
{
        if (ni->unwinding) {
                ni->unwinding = false;
                if (ni->host_failure != NULL) {
                        R_ReleaseObject(ni->host_failure);
                        ni->host_failure = NULL;
                }
                R_ContinueUnwind(nw_unwind_token);
        }
        SEXP failure = ni->host_failure;
        if (failure != NULL) {
                ni->host_failure = NULL;
                PROTECT(failure);
                R_ReleaseObject(failure);
                UNPROTECT(1);
        }
        return failure;
}
