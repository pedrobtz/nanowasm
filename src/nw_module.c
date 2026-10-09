/*
 * Modules: loading, validation and introspection.
 */
#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include "nanowasm.h"

#include "toywasm/load_context.h"
#include "toywasm/module.h"
#include "toywasm/report.h"

static SEXP
module_tag(void)
{
        static SEXP tag = NULL;
        if (tag == NULL) {
                tag = Rf_install("nanowasm_module");
        }
        return tag;
}

void
nw_module_release(struct nw_module *nm)
{
        if (nm == NULL || --nm->refs > 0) {
                return;
        }
        if (nm->module != NULL) {
                module_destroy(&nm->mctx, nm->module);
        }
        mem_context_clear(&nm->mctx);
        free(nm->bytes);
        free(nm);
}

static void
module_finalize(SEXP ptr)
{
        struct nw_module *nm = R_ExternalPtrAddr(ptr);
        R_ClearExternalPtr(ptr);
        nw_module_release(nm);
}

/* The R wrappers check liveness first, so a NULL here is a package bug. */
struct nw_module *
nw_module_get(SEXP ptr)
{
        if (TYPEOF(ptr) != EXTPTRSXP || R_ExternalPtrTag(ptr) != module_tag()) {
                Rf_error("internal error: not a nanowasm module pointer");
        }
        struct nw_module *nm = R_ExternalPtrAddr(ptr);
        if (nm == NULL || nm->module == NULL) {
                Rf_error("internal error: dead nanowasm module pointer");
        }
        return nm;
}

/* Whether an external pointer still points at something (it is NULL after
   a saveRDS()/readRDS() round trip). */
SEXP
nw_ptr_is_live(SEXP ptr)
{
        return Rf_ScalarLogical(TYPEOF(ptr) == EXTPTRSXP &&
                                R_ExternalPtrAddr(ptr) != NULL);
}

/*
 * The legacy exception-handling instructions (try 06, catch 07, rethrow 09,
 * delegate 18, catch_all 19), which toywasm doesn't implement, are what
 * wasi-sdk and Emscripten still emit by default. Say how to rebuild.
 */
static const char *
legacy_eh_hint(const char *detail)
{
        static const char *const opcodes[] = {"06", "07", "09", "18", "19"};
        if (detail == NULL || strstr(detail, "group 'base'") == NULL) {
                return "";
        }
        for (size_t i = 0; i < sizeof(opcodes) / sizeof(opcodes[0]); i++) {
                char needle[32];
                snprintf(needle, sizeof(needle), "instruction %s ", opcodes[i]);
                if (strstr(detail, needle) != NULL) {
                        return " The module uses the legacy encoding of "
                               "WebAssembly exceptions, which nanowasm "
                               "doesn't support; rebuild it with "
                               "`-mllvm -wasm-use-legacy-eh=false`.";
                }
        }
        return "";
}

SEXP
nw_module_load(SEXP bytes)
{
        if (TYPEOF(bytes) != RAWSXP) {
                Rf_error("internal error: module bytes must be a raw vector");
        }
        R_xlen_t n = XLENGTH(bytes);

        /* Own the pointer before owning anything else, so an R error from
           here on leaks nothing: the finalizer frees whatever exists. */
        SEXP ptr = PROTECT(R_MakeExternalPtr(NULL, module_tag(), R_NilValue));
        R_RegisterCFinalizerEx(ptr, module_finalize, TRUE);
        struct nw_module *nm = calloc(1, sizeof(*nm));
        if (nm == NULL) {
                UNPROTECT(1);
                return nw_fail_errno(ENOMEM, "Could not load the module");
        }
        nm->refs = 1;
        mem_context_init(&nm->mctx);
        R_SetExternalPtrAddr(ptr, nm);

        /* A private copy: the module points into these bytes for as long as
           it lives, and R's raw vector may be modified or collected. */
        nm->bytes = malloc(n > 0 ? (size_t)n : 1);
        if (nm->bytes == NULL) {
                UNPROTECT(1);
                return nw_fail_errno(ENOMEM, "Could not load the module");
        }
        if (n > 0) {
                memcpy(nm->bytes, RAW(bytes), (size_t)n);
        }
        nm->nbytes = (size_t)n;

        struct load_context lctx;
        load_context_init(&lctx, &nm->mctx);
        int ret = module_create(&nm->module, nm->bytes, nm->bytes + n, &lctx);
        char msg[1024] = "";
        if (ret != 0) {
                const char *detail = report_getmessage(&lctx.report);
                snprintf(msg, sizeof(msg), "Invalid WebAssembly module: %s.%s",
                         detail != NULL && detail[0] != '\0'
                                 ? detail
                                 : "failed to decode or validate",
                         legacy_eh_hint(detail));
        }
        load_context_clear(&lctx);
        if (ret != 0) {
                nm->module = NULL;
                UNPROTECT(1);
                return nw_fail("nanowasm_validation_error", msg);
        }
        UNPROTECT(1);
        return ptr;
}

const char *
nw_valtype_name(enum valtype t)
{
        switch (t) {
        case TYPE_i32:
                return "i32";
        case TYPE_i64:
                return "i64";
        case TYPE_f32:
                return "f32";
        case TYPE_f64:
                return "f64";
        case TYPE_v128:
                return "v128";
        case TYPE_funcref:
                return "funcref";
        case TYPE_externref:
                return "externref";
        case TYPE_exnref:
                return "exnref";
        default:
                return "unknown";
        }
}

/* A growable string for building type descriptions. */
struct strbuf {
        char buf[1024];
        size_t len;
};

static void
sb_add(struct strbuf *sb, const char *s)
{
        size_t n = strlen(s);
        if (sb->len + n >= sizeof(sb->buf)) {
                n = sizeof(sb->buf) - 1 - sb->len;
        }
        memcpy(sb->buf + sb->len, s, n);
        sb->len += n;
        sb->buf[sb->len] = '\0';
}

static void
sb_resulttype(struct strbuf *sb, const struct resulttype *rt)
{
        sb_add(sb, "(");
        for (uint32_t i = 0; i < rt->ntypes; i++) {
                if (i > 0) {
                        sb_add(sb, ", ");
                }
                sb_add(sb, nw_valtype_name(rt->types[i]));
        }
        sb_add(sb, ")");
}

/* "(i32, i32) -> i32", "(i32) -> (i64, i32)", "() -> ()" */
static void
sb_functype(struct strbuf *sb, const struct functype *ft)
{
        sb_resulttype(sb, &ft->parameter);
        sb_add(sb, " -> ");
        if (ft->result.ntypes == 1) {
                sb_add(sb, nw_valtype_name(ft->result.types[0]));
        } else {
                sb_resulttype(sb, &ft->result);
        }
}

/*
 * "min 1 max 2", "min 1". toywasm stores an absent maximum as the largest
 * the type allows (UINT32_MAX elements for tables, 65536 pages for 32-bit
 * memories), so a maximum equal to that ceiling is not shown: the two mean
 * the same thing.
 */
static void
sb_limits(struct strbuf *sb, const struct limits *lim, uint32_t ceiling)
{
        char tmp[64];
        snprintf(tmp, sizeof(tmp), "min %u", (unsigned)lim->min);
        sb_add(sb, tmp);
        if (lim->max != ceiling) {
                snprintf(tmp, sizeof(tmp), " max %u", (unsigned)lim->max);
                sb_add(sb, tmp);
        }
}

static uint32_t
memory_ceiling(const struct memtype *mt)
{
        uint64_t pages = WASM_MAX_MEMORY_SIZE >> memtype_page_shift(mt);
        return pages > UINT32_MAX ? UINT32_MAX : (uint32_t)pages;
}

static void
sb_globaltype(struct strbuf *sb, const struct globaltype *gt)
{
        if (gt->mut == GLOBAL_VAR) {
                sb_add(sb, "mut ");
        }
        sb_add(sb, nw_valtype_name(gt->t));
}

static const char *
externtype_name(enum externtype t)
{
        switch (t) {
        case EXTERNTYPE_FUNC:
                return "function";
        case EXTERNTYPE_TABLE:
                return "table";
        case EXTERNTYPE_MEMORY:
                return "memory";
        case EXTERNTYPE_GLOBAL:
                return "global";
#if defined(TOYWASM_ENABLE_WASM_EXCEPTION_HANDLING)
        case EXTERNTYPE_TAG:
                return "tag";
#endif
        default:
                return "unknown";
        }
}

static SEXP
mk_name(const struct name *name)
{
        return Rf_mkCharLenCE(name->data, (int)name->nbytes, CE_UTF8);
}

/* list(name, kind, type) for the module's exports, in module order. */
SEXP
nw_module_exports(SEXP ptr)
{
        const struct module *m = nw_module_get(ptr)->module;
        R_xlen_t n = m->nexports;
        SEXP name = PROTECT(Rf_allocVector(STRSXP, n));
        SEXP kind = PROTECT(Rf_allocVector(STRSXP, n));
        SEXP type = PROTECT(Rf_allocVector(STRSXP, n));
        for (R_xlen_t i = 0; i < n; i++) {
                const struct wasm_export *ex = &m->exports[i];
                struct strbuf sb = {"", 0};
                uint32_t idx = ex->desc.idx;
                switch (ex->desc.type) {
                case EXTERNTYPE_FUNC:
                        sb_functype(&sb, module_functype(m, idx));
                        break;
                case EXTERNTYPE_TABLE: {
                        const struct tabletype *tt = module_tabletype(m, idx);
                        sb_add(&sb, nw_valtype_name(tt->et));
                        sb_add(&sb, " ");
                        sb_limits(&sb, &tt->lim, UINT32_MAX);
                        break;
                }
                case EXTERNTYPE_MEMORY: {
                        const struct memtype *mt = module_memtype(m, idx);
                        sb_limits(&sb, &mt->lim, memory_ceiling(mt));
                        break;
                }
                case EXTERNTYPE_GLOBAL:
                        sb_globaltype(&sb, module_globaltype(m, idx));
                        break;
#if defined(TOYWASM_ENABLE_WASM_EXCEPTION_HANDLING)
                case EXTERNTYPE_TAG:
                        /* An exception tag: the types it carries. */
                        sb_resulttype(&sb, &module_tagtype_functype(m, module_tagtype(m, idx))->parameter);
                        break;
#endif
                default:
                        break;
                }
                SET_STRING_ELT(name, i, mk_name(&ex->name));
                SET_STRING_ELT(kind, i, Rf_mkChar(externtype_name(ex->desc.type)));
                SET_STRING_ELT(type, i, Rf_mkChar(sb.buf));
        }
        SEXP res = PROTECT(Rf_allocVector(VECSXP, 3));
        SET_VECTOR_ELT(res, 0, name);
        SET_VECTOR_ELT(res, 1, kind);
        SET_VECTOR_ELT(res, 2, type);
        UNPROTECT(4);
        return res;
}

/* list(module, name, kind, type) for the module's imports. */
SEXP
nw_module_imports(SEXP ptr)
{
        const struct module *m = nw_module_get(ptr)->module;
        R_xlen_t n = m->nimports;
        SEXP modname = PROTECT(Rf_allocVector(STRSXP, n));
        SEXP name = PROTECT(Rf_allocVector(STRSXP, n));
        SEXP kind = PROTECT(Rf_allocVector(STRSXP, n));
        SEXP type = PROTECT(Rf_allocVector(STRSXP, n));
        for (R_xlen_t i = 0; i < n; i++) {
                const struct import *im = &m->imports[i];
                const struct importdesc *d = &im->desc;
                struct strbuf sb = {"", 0};
                switch (d->type) {
                case EXTERNTYPE_FUNC:
                        sb_functype(&sb, &m->types[d->u.typeidx]);
                        break;
                case EXTERNTYPE_TABLE:
                        sb_add(&sb, nw_valtype_name(d->u.tabletype.et));
                        sb_add(&sb, " ");
                        sb_limits(&sb, &d->u.tabletype.lim, UINT32_MAX);
                        break;
                case EXTERNTYPE_MEMORY:
                        sb_limits(&sb, &d->u.memtype.lim,
                                  memory_ceiling(&d->u.memtype));
                        break;
                case EXTERNTYPE_GLOBAL:
                        sb_globaltype(&sb, &d->u.globaltype);
                        break;
#if defined(TOYWASM_ENABLE_WASM_EXCEPTION_HANDLING)
                case EXTERNTYPE_TAG:
                        sb_resulttype(&sb, &module_tagtype_functype(m, &d->u.tagtype)->parameter);
                        break;
#endif
                default:
                        break;
                }
                SET_STRING_ELT(modname, i, mk_name(&im->module_name));
                SET_STRING_ELT(name, i, mk_name(&im->name));
                SET_STRING_ELT(kind, i, Rf_mkChar(externtype_name(d->type)));
                SET_STRING_ELT(type, i, Rf_mkChar(sb.buf));
        }
        SEXP res = PROTECT(Rf_allocVector(VECSXP, 4));
        SET_VECTOR_ELT(res, 0, modname);
        SET_VECTOR_ELT(res, 1, name);
        SET_VECTOR_ELT(res, 2, kind);
        SET_VECTOR_ELT(res, 3, type);
        UNPROTECT(5);
        return res;
}
