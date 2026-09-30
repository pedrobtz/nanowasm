/*
 * Instances: instantiation, calls, and conversion of values between R and
 * WebAssembly.
 *
 * Execution follows one rule: while an exec_context is live, nothing here
 * allocates R memory or can raise an R error. Arguments are converted
 * before execution starts, results are copied into C memory and the context
 * is cleared before any R value is built.
 */
#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "nanowasm.h"

#include "toywasm/instance.h"
#include "toywasm/module.h"
#include "toywasm/report.h"

/* 2^53: the largest magnitude below which every integer is a double. */
#define NW_MAX_SAFE_INTEGER 9007199254740992.0

static SEXP
instance_tag(void)
{
        static SEXP tag = NULL;
        if (tag == NULL) {
                tag = Rf_install("nanowasm_instance");
        }
        return tag;
}

static void
instance_release(struct nw_instance *ni)
{
        if (ni == NULL || --ni->refs > 0) {
                return;
        }
        if (ni->inst != NULL) {
                instance_destroy(ni->inst);
        }
        mem_context_clear(&ni->mctx);
        nw_module_release(ni->mod);
        free(ni);
}

static void
instance_finalize(SEXP ptr)
{
        struct nw_instance *ni = R_ExternalPtrAddr(ptr);
        R_ClearExternalPtr(ptr);
        instance_release(ni);
}

struct nw_instance *
nw_instance_get(SEXP ptr)
{
        if (TYPEOF(ptr) != EXTPTRSXP ||
            R_ExternalPtrTag(ptr) != instance_tag()) {
                Rf_error("internal error: not a nanowasm instance pointer");
        }
        struct nw_instance *ni = R_ExternalPtrAddr(ptr);
        if (ni == NULL || ni->inst == NULL) {
                Rf_error("internal error: dead nanowasm instance pointer");
        }
        return ni;
}

/* The outcome of running Wasm code, captured before the context is
   cleared: either success or everything needed to describe the failure. */
struct run_result {
        int ret;
        struct trap_info trap;
        char detail[512];
};

static void
run_init(struct exec_context *ctx, struct nw_instance *ni)
{
        exec_context_init(ctx, ni->inst, &ni->mctx);
        ctx->options = ni->options;
}

static void
run_finish(struct exec_context *ctx, int ret, struct run_result *rr)
{
        while (IS_RESTARTABLE(ret)) {
                ret = instance_execute_handle_restart_once(ctx, ret);
        }
        rr->ret = ret;
        rr->detail[0] = '\0';
        if (ret == ETOYWASMTRAP) {
                rr->trap = ctx->trap;
                const char *msg = report_getmessage(ctx->report);
                if (msg != NULL) {
                        snprintf(rr->detail, sizeof(rr->detail), "%s", msg);
                }
        }
}

static SEXP
run_failure(const struct run_result *rr, const char *what)
{
        if (rr->ret == ETOYWASMTRAP) {
                return nw_fail_trap(&rr->trap, rr->detail);
        }
        return nw_fail_errno(rr->ret, what);
}

SEXP
nw_instantiate(SEXP modptr)
{
        struct nw_module *nm = nw_module_get(modptr);
        if (nm->module->nimports > 0) {
                return nw_fail("nanowasm_link_error",
                               "The module has imports, which are not "
                               "supported yet.");
        }

        SEXP ptr = PROTECT(R_MakeExternalPtr(NULL, instance_tag(), modptr));
        R_RegisterCFinalizerEx(ptr, instance_finalize, TRUE);
        struct nw_instance *ni = calloc(1, sizeof(*ni));
        if (ni == NULL) {
                UNPROTECT(1);
                return nw_fail_errno(ENOMEM, "Could not instantiate the module");
        }
        ni->refs = 1;
        ni->mod = nm;
        nm->refs++;
        mem_context_init(&ni->mctx);
        exec_options_set_defaults(&ni->options);
        ni->options.max_frames = NW_DEFAULT_MAX_FRAMES;
        ni->options.max_stackcells = NW_DEFAULT_MAX_STACKCELLS;
        R_SetExternalPtrAddr(ptr, ni);

        struct report report;
        report_init(&report);
        int ret = instance_create_no_init(&ni->mctx, nm->module, &ni->inst,
                                          NULL, &report);
        if (ret != 0) {
                char msg[512];
                const char *detail = report_getmessage(&report);
                snprintf(msg, sizeof(msg), "Could not instantiate the module: %s.",
                         detail != NULL && detail[0] != '\0' ? detail
                                                             : strerror(ret));
                report_clear(&report);
                ni->inst = NULL;
                UNPROTECT(1);
                return nw_fail(ret == ENOMEM ? "nanowasm_memory_limit"
                                             : "nanowasm_link_error",
                               msg);
        }
        report_clear(&report);

        /* Data and element segments, then the start function. */
        struct exec_context ctx;
        struct run_result rr;
        run_init(&ctx, ni);
        run_finish(&ctx, instance_execute_init(&ctx), &rr);
        exec_context_clear(&ctx);
        if (rr.ret != 0) {
                UNPROTECT(1);
                return run_failure(&rr, "Could not instantiate the module");
        }
        UNPROTECT(1);
        return ptr;
}

static bool
is_supported(enum valtype t)
{
        return t == TYPE_i32 || t == TYPE_i64 || t == TYPE_f32 ||
               t == TYPE_f64;
}

static SEXP
fail_arg(const char *func, R_xlen_t i, enum valtype t, const char *why)
{
        char msg[512];
        snprintf(msg, sizeof(msg),
                 "Argument %d of `%s` (%s) %s.", (int)(i + 1), func,
                 nw_valtype_name(t), why);
        return nw_fail("nanowasm_argument_error", msg);
}

/*
 * Convert one R argument to a Wasm value of type t. Returns R_NilValue on
 * success, or a failure.
 */
static SEXP
arg_to_val(SEXP x, enum valtype t, const char *func, R_xlen_t i,
           struct val *v)
{
        if (TYPEOF(x) != INTSXP && TYPEOF(x) != REALSXP) {
                return fail_arg(func, i, t, "must be an integer or double");
        }
        if (XLENGTH(x) != 1) {
                return fail_arg(func, i, t, "must have length 1");
        }
        bool is_int = TYPEOF(x) == INTSXP;
        int iv = is_int ? INTEGER(x)[0] : 0;
        double dv = is_int ? 0 : REAL(x)[0];
        switch (t) {
        case TYPE_i32:
                /* NA_integer_ has INT_MIN's bit pattern and passes as that. */
                if (is_int) {
                        v->u.i32 = (uint32_t)iv;
                        return R_NilValue;
                }
                if (!isfinite(dv) || dv != floor(dv) || dv < -2147483648.0 ||
                    dv >= 4294967296.0) {
                        return fail_arg(func, i, t,
                                        "must be a whole number in "
                                        "[-2^31, 2^32)");
                }
                v->u.i32 = dv < 0 ? (uint32_t)(int32_t)dv : (uint32_t)dv;
                return R_NilValue;
        case TYPE_i64:
                if (is_int) {
                        if (iv == NA_INTEGER) {
                                return fail_arg(func, i, t, "must not be NA");
                        }
                        v->u.i64 = (uint64_t)(int64_t)iv;
                        return R_NilValue;
                }
                if (!isfinite(dv) || dv != floor(dv) ||
                    fabs(dv) > NW_MAX_SAFE_INTEGER) {
                        return fail_arg(func, i, t,
                                        "must be a whole number in "
                                        "[-2^53, 2^53]");
                }
                v->u.i64 = (uint64_t)(int64_t)dv;
                return R_NilValue;
        case TYPE_f32:
                v->u.f32 = is_int ? (iv == NA_INTEGER ? (float)NAN : (float)iv)
                                  : (float)dv;
                return R_NilValue;
        case TYPE_f64:
                v->u.f64 = is_int ? (iv == NA_INTEGER ? NA_REAL : (double)iv)
                                  : dv;
                return R_NilValue;
        default:
                return fail_arg(func, i, t, "has an unsupported type");
        }
}

/* Convert one Wasm result to R. Returns NULL (not R_NilValue) if an i64
   does not fit a double exactly. */
static SEXP
val_to_sexp(const struct val *v, enum valtype t)
{
        switch (t) {
        case TYPE_i32:
                return Rf_ScalarInteger((int32_t)v->u.i32);
        case TYPE_i64: {
                int64_t x = (int64_t)v->u.i64;
                if (x > (int64_t)NW_MAX_SAFE_INTEGER ||
                    x < -(int64_t)NW_MAX_SAFE_INTEGER) {
                        return NULL;
                }
                return Rf_ScalarReal((double)x);
        }
        case TYPE_f32:
                return Rf_ScalarReal((double)v->u.f32);
        case TYPE_f64:
                return Rf_ScalarReal(v->u.f64);
        default:
                return R_NilValue;
        }
}

static SEXP
fail_unsupported(const char *func, const char *where, enum valtype t)
{
        char msg[512];
        snprintf(msg, sizeof(msg),
                 "`%s` has a %s of type %s, which nanowasm cannot pass "
                 "between R and WebAssembly.",
                 func, where, nw_valtype_name(t));
        return nw_fail("nanowasm_unsupported", msg);
}

SEXP
nw_call(SEXP instptr, SEXP name, SEXP args)
{
        struct nw_instance *ni = nw_instance_get(instptr);
        const struct module *m = ni->mod->module;
        const char *fname = Rf_translateCharUTF8(STRING_ELT(name, 0));
        struct name wname = {(uint32_t)strlen(fname), fname};
        char msg[512];

        uint32_t funcidx;
        if (module_find_export(m, &wname, EXTERNTYPE_FUNC, &funcidx) != 0) {
                snprintf(msg, sizeof(msg),
                         "The instance has no exported function named `%s`.",
                         fname);
                return nw_fail("nanowasm_argument_error", msg);
        }
        const struct functype *ft = module_functype(m, funcidx);
        const struct resulttype *pt = &ft->parameter;
        const struct resulttype *rt = &ft->result;
        for (uint32_t i = 0; i < pt->ntypes; i++) {
                if (!is_supported(pt->types[i])) {
                        return fail_unsupported(fname, "parameter", pt->types[i]);
                }
        }
        for (uint32_t i = 0; i < rt->ntypes; i++) {
                if (!is_supported(rt->types[i])) {
                        return fail_unsupported(fname, "result", rt->types[i]);
                }
        }
        R_xlen_t nargs = XLENGTH(args);
        if (nargs != (R_xlen_t)pt->ntypes) {
                snprintf(msg, sizeof(msg),
                         "`%s` takes %u argument%s but was given %d.", fname,
                         (unsigned)pt->ntypes, pt->ntypes == 1 ? "" : "s",
                         (int)nargs);
                return nw_fail("nanowasm_argument_error", msg);
        }

        /* R_alloc memory is released when .Call returns. */
        struct val *params =
                (struct val *)R_alloc(pt->ntypes + 1, sizeof(struct val));
        struct val *results =
                (struct val *)R_alloc(rt->ntypes + 1, sizeof(struct val));
        for (R_xlen_t i = 0; i < nargs; i++) {
                SEXP fail = arg_to_val(VECTOR_ELT(args, i), pt->types[i],
                                       fname, i, &params[i]);
                if (fail != R_NilValue) {
                        return fail;
                }
        }

        struct exec_context ctx;
        struct run_result rr;
        run_init(&ctx, ni);
        int ret = exec_push_vals(&ctx, pt, params);
        if (ret == 0) {
                ret = instance_execute_func(&ctx, funcidx, pt, rt);
        }
        run_finish(&ctx, ret, &rr);
        if (rr.ret == 0) {
                exec_pop_vals(&ctx, rt, results);
        }
        exec_context_clear(&ctx);
        if (rr.ret != 0) {
                snprintf(msg, sizeof(msg), "Could not call `%s`", fname);
                return run_failure(&rr, msg);
        }

        if (rt->ntypes == 0) {
                return R_NilValue;
        }
        SEXP out = PROTECT(Rf_allocVector(VECSXP, rt->ntypes));
        for (uint32_t i = 0; i < rt->ntypes; i++) {
                SEXP v = val_to_sexp(&results[i], rt->types[i]);
                if (v == NULL) {
                        UNPROTECT(1);
                        snprintf(msg, sizeof(msg),
                                 "Result %u of `%s` (i64) is %lld, which a "
                                 "double cannot represent exactly.",
                                 (unsigned)(i + 1), fname,
                                 (long long)(int64_t)results[i].u.i64);
                        return nw_fail2("nanowasm_precision_error",
                                        "nanowasm_argument_error", msg);
                }
                SET_VECTOR_ELT(out, i, v);
        }
        UNPROTECT(1);
        return rt->ntypes == 1 ? VECTOR_ELT(out, 0) : out;
}
