/*
 * Linear memory: size, growth, and typed reads and writes from R.
 *
 * Offsets are byte addresses, as in WebAssembly. Every access is checked
 * against the memory's current size, and the data pointer is fetched afresh
 * each time because memory.grow can move it. WebAssembly memory is
 * little-endian; values go through toywasm's endian helpers so the host's
 * byte order never matters.
 */
#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "nanowasm.h"

#include "toywasm/endian.h"
#include "toywasm/instance.h"
#include "toywasm/module.h"

#define NW_MAX_SAFE_INTEGER 9007199254740992.0

/* Element types, in the order of R's `types` vector in R/memory.R. */
enum nw_elem {
        NW_RAW,
        NW_I8,
        NW_U8,
        NW_I16,
        NW_U16,
        NW_I32,
        NW_U32,
        NW_I64,
        NW_U64,
        NW_F32,
        NW_F64,
};

static const char *const elem_names[] = {"raw", "i8",  "u8",  "i16",
                                         "u16", "i32", "u32", "i64",
                                         "u64", "f32", "f64"};

static size_t
elem_size(enum nw_elem e)
{
        switch (e) {
        case NW_RAW:
        case NW_I8:
        case NW_U8:
                return 1;
        case NW_I16:
        case NW_U16:
                return 2;
        case NW_I32:
        case NW_U32:
        case NW_F32:
                return 4;
        default:
                return 8;
        }
}

static struct meminst *
get_memory(SEXP instptr, SEXP memidx, struct nw_instance **nip)
{
        struct nw_instance *ni = nw_instance_get(instptr);
        uint32_t idx = (uint32_t)Rf_asInteger(memidx);
        if (idx >= ni->inst->mems.lsize) {
                Rf_error("internal error: memory index out of range");
        }
        if (nip != NULL) {
                *nip = ni;
        }
        return VEC_ELEM(ni->inst->mems, idx);
}

static uint64_t
memory_bytes(const struct meminst *mi)
{
        return (uint64_t)mi->size_in_pages << memtype_page_shift(mi->type);
}

/* The index of the memory exported as `name`, or a failure. */
SEXP
nw_memory_index(SEXP instptr, SEXP name)
{
        struct nw_instance *ni = nw_instance_get(instptr);
        const char *mname = Rf_translateCharUTF8(STRING_ELT(name, 0));
        struct name wname = {(uint32_t)strlen(mname), mname};
        uint32_t idx;
        if (module_find_export(ni->mod->module, &wname, EXTERNTYPE_MEMORY,
                               &idx) != 0) {
                char msg[512];
                snprintf(msg, sizeof(msg),
                         "The instance has no exported memory named `%s`.",
                         mname);
                return nw_fail("nanowasm_argument_error", msg);
        }
        return Rf_ScalarInteger((int)idx);
}

/* c(bytes, pages, page size) */
SEXP
nw_memory_size(SEXP instptr, SEXP memidx)
{
        struct meminst *mi = get_memory(instptr, memidx, NULL);
        SEXP res = PROTECT(Rf_allocVector(REALSXP, 3));
        REAL(res)[0] = (double)memory_bytes(mi);
        REAL(res)[1] = (double)mi->size_in_pages;
        REAL(res)[2] = (double)memtype_page_size(mi->type);
        UNPROTECT(1);
        return res;
}

/* The previous size in pages, or a failure. */
SEXP
nw_memory_grow(SEXP instptr, SEXP memidx, SEXP pages)
{
        struct nw_instance *ni;
        struct meminst *mi = get_memory(instptr, memidx, &ni);
        double delta = REAL(pages)[0];
        uint32_t max = mi->type->lim.max;
        uint32_t cur = mi->size_in_pages;
        char msg[512];
        if (delta > (double)(max - cur)) {
                snprintf(msg, sizeof(msg),
                         "Can't grow the memory by %.0f pages: it has %u and "
                         "its maximum is %u.",
                         delta, (unsigned)cur, (unsigned)max);
                return nw_fail("nanowasm_memory_limit", msg);
        }
        uint32_t old = memory_grow(mi, (uint32_t)delta);
        if (old == (uint32_t)-1) {
                snprintf(msg, sizeof(msg),
                         "Can't grow the memory by %.0f pages: the instance's "
                         "memory limit would be exceeded.",
                         delta);
                return nw_fail("nanowasm_memory_limit", msg);
        }
        return Rf_ScalarReal((double)old);
}

static SEXP
fail_bounds(uint64_t offset, uint64_t nbytes, uint64_t size)
{
        char msg[512];
        snprintf(msg, sizeof(msg),
                 "Access of %llu bytes at offset %llu is out of bounds of the "
                 "memory (%llu bytes).",
                 (unsigned long long)nbytes, (unsigned long long)offset,
                 (unsigned long long)size);
        return nw_fail2("nanowasm_out_of_bounds", "nanowasm_argument_error",
                        msg);
}

/*
 * A pointer to nbytes at offset, after checking the bounds. toywasm
 * allocates memory lazily, so this can allocate (counted against the
 * instance's memory limit) and move the data. Returns R_NilValue and sets
 * *pp on success, or a failure.
 */
static SEXP
span(struct meminst *mi, double offset, uint64_t nbytes, uint8_t **pp)
{
        uint64_t size = memory_bytes(mi);
        if (!(offset >= 0) || offset > (double)size ||
            nbytes > size - (uint64_t)offset) {
                return fail_bounds(offset >= 0 ? (uint64_t)offset : 0, nbytes,
                                   size);
        }
        static uint8_t empty;
        if (nbytes == 0) {
                *pp = &empty;
                return R_NilValue;
        }
        void *p;
        int ret = memory_instance_getptr2(mi, (uint32_t)offset, 0,
                                          (uint32_t)nbytes, &p, NULL);
        if (ret == ENOMEM) {
                return nw_fail_errno(ENOMEM, "Could not access the memory");
        }
        if (ret != 0) {
                return fail_bounds((uint64_t)offset, nbytes, size);
        }
        *pp = p;
        return R_NilValue;
}

SEXP
nw_memory_read(SEXP instptr, SEXP memidx, SEXP offset, SEXP n, SEXP type)
{
        struct meminst *mi = get_memory(instptr, memidx, NULL);
        enum nw_elem e = (enum nw_elem)Rf_asInteger(type);
        double count = REAL(n)[0];
        size_t esize = elem_size(e);
        if (count > (double)UINT32_MAX) {
                return fail_bounds((uint64_t)REAL(offset)[0], UINT64_MAX,
                                   memory_bytes(mi));
        }
        uint64_t nbytes = (uint64_t)count * esize;
        uint8_t *p;
        SEXP fail = span(mi, REAL(offset)[0], nbytes, &p);
        if (fail != R_NilValue) {
                return fail;
        }
        R_xlen_t len = (R_xlen_t)count;

        /* Allocating the result can't move Wasm memory, but copy through a
           private buffer anyway so no R allocation happens while p is held. */
        uint8_t *buf = (uint8_t *)R_alloc(nbytes + 1, 1);
        memcpy(buf, p, nbytes);

        SEXP res;
        switch (e) {
        case NW_RAW:
                res = PROTECT(Rf_allocVector(RAWSXP, len));
                memcpy(RAW(res), buf, nbytes);
                break;
        case NW_I8:
        case NW_U8:
        case NW_I16:
        case NW_U16:
        case NW_I32: {
                res = PROTECT(Rf_allocVector(INTSXP, len));
                int *out = INTEGER(res);
                for (R_xlen_t i = 0; i < len; i++) {
                        const uint8_t *q = buf + i * esize;
                        switch (e) {
                        case NW_I8:
                                out[i] = (int8_t)q[0];
                                break;
                        case NW_U8:
                                out[i] = q[0];
                                break;
                        case NW_I16:
                                out[i] = (int16_t)le16_decode(q);
                                break;
                        case NW_U16:
                                out[i] = le16_decode(q);
                                break;
                        default:
                                out[i] = (int32_t)le32_decode(q);
                                break;
                        }
                }
                break;
        }
        default: {
                res = PROTECT(Rf_allocVector(REALSXP, len));
                double *out = REAL(res);
                for (R_xlen_t i = 0; i < len; i++) {
                        const uint8_t *q = buf + i * esize;
                        switch (e) {
                        case NW_U32:
                                out[i] = le32_decode(q);
                                break;
                        case NW_F32:
                                out[i] = lef32_decode(q);
                                break;
                        case NW_F64:
                                out[i] = lef64_decode(q);
                                break;
                        case NW_I64: {
                                int64_t v = (int64_t)le64_decode(q);
                                if (v > (int64_t)NW_MAX_SAFE_INTEGER ||
                                    v < -(int64_t)NW_MAX_SAFE_INTEGER) {
                                        UNPROTECT(1);
                                        goto precision;
                                }
                                out[i] = (double)v;
                                break;
                        }
                        default: { /* NW_U64 */
                                uint64_t v = le64_decode(q);
                                if (v > (uint64_t)NW_MAX_SAFE_INTEGER) {
                                        UNPROTECT(1);
                                        goto precision;
                                }
                                out[i] = (double)v;
                                break;
                        }
                        }
                }
                break;
        }
        }
        UNPROTECT(1);
        return res;

precision : {
        char msg[256];
        snprintf(msg, sizeof(msg),
                 "The memory holds a %s value that a double cannot represent "
                 "exactly.",
                 elem_names[e]);
        return nw_fail2("nanowasm_precision_error", "nanowasm_argument_error",
                        msg);
}
}

static SEXP
fail_value(enum nw_elem e, R_xlen_t i, const char *why)
{
        char msg[512];
        snprintf(msg, sizeof(msg), "Element %lld of `x` %s for type %s.",
                 (long long)(i + 1), why, elem_names[e]);
        return nw_fail("nanowasm_argument_error", msg);
}

/* Range of the integer element types, as doubles. */
static void
int_range(enum nw_elem e, double *lo, double *hi)
{
        switch (e) {
        case NW_I8:
                *lo = -128;
                *hi = 127;
                break;
        case NW_U8:
                *lo = 0;
                *hi = 255;
                break;
        case NW_I16:
                *lo = -32768;
                *hi = 32767;
                break;
        case NW_U16:
                *lo = 0;
                *hi = 65535;
                break;
        case NW_I32:
                *lo = -2147483648.0;
                *hi = 2147483647.0;
                break;
        case NW_U32:
                *lo = 0;
                *hi = 4294967295.0;
                break;
        case NW_I64:
                *lo = -NW_MAX_SAFE_INTEGER;
                *hi = NW_MAX_SAFE_INTEGER;
                break;
        default: /* NW_U64 */
                *lo = 0;
                *hi = NW_MAX_SAFE_INTEGER;
                break;
        }
}

/*
 * Write x at offset. The whole vector is converted and range-checked into a
 * buffer first, so a bad element leaves the memory untouched. Returns the
 * offset just past the written bytes.
 */
SEXP
nw_memory_write(SEXP instptr, SEXP memidx, SEXP offset, SEXP x, SEXP type)
{
        struct meminst *mi = get_memory(instptr, memidx, NULL);
        enum nw_elem e = (enum nw_elem)Rf_asInteger(type);
        size_t esize = elem_size(e);
        R_xlen_t len = XLENGTH(x);
        uint64_t nbytes = (uint64_t)len * esize;
        if (nbytes > memory_bytes(mi)) {
                return fail_bounds((uint64_t)REAL(offset)[0], nbytes,
                                   memory_bytes(mi));
        }
        uint8_t *buf = (uint8_t *)R_alloc(nbytes + 1, 1);

        if (e == NW_RAW) {
                if (TYPEOF(x) != RAWSXP) {
                        return nw_fail("nanowasm_argument_error",
                                       "`x` must be a raw vector for type raw.");
                }
                memcpy(buf, RAW(x), nbytes);
        } else if (TYPEOF(x) != INTSXP && TYPEOF(x) != REALSXP) {
                char msg[128];
                snprintf(msg, sizeof(msg),
                         "`x` must be an integer or double vector for type %s.",
                         elem_names[e]);
                return nw_fail("nanowasm_argument_error", msg);
        } else if (e == NW_F32 || e == NW_F64) {
                for (R_xlen_t i = 0; i < len; i++) {
                        double v;
                        if (TYPEOF(x) == INTSXP) {
                                int iv = INTEGER(x)[i];
                                v = iv == NA_INTEGER ? NA_REAL : (double)iv;
                        } else {
                                v = REAL(x)[i];
                        }
                        if (e == NW_F32) {
                                lef32_encode(buf + i * esize, (float)v);
                        } else {
                                lef64_encode(buf + i * esize, v);
                        }
                }
        } else {
                double lo, hi;
                int_range(e, &lo, &hi);
                for (R_xlen_t i = 0; i < len; i++) {
                        double v;
                        if (TYPEOF(x) == INTSXP) {
                                int iv = INTEGER(x)[i];
                                if (iv == NA_INTEGER) {
                                        return fail_value(e, i, "is NA");
                                }
                                v = iv;
                        } else {
                                v = REAL(x)[i];
                                if (!isfinite(v) || v != floor(v)) {
                                        return fail_value(
                                                e, i, "is not a whole number");
                                }
                        }
                        if (v < lo || v > hi) {
                                return fail_value(e, i, "is out of range");
                        }
                        uint8_t *q = buf + i * esize;
                        switch (esize) {
                        case 1:
                                q[0] = (uint8_t)(int64_t)v;
                                break;
                        case 2:
                                le16_encode(q, (uint16_t)(int64_t)v);
                                break;
                        case 4:
                                le32_encode(q, (uint32_t)(int64_t)v);
                                break;
                        default:
                                le64_encode(q, (uint64_t)(int64_t)v);
                                break;
                        }
                }
        }

        uint8_t *p;
        SEXP fail = span(mi, REAL(offset)[0], nbytes, &p);
        if (fail != R_NilValue) {
                return fail;
        }
        memcpy(p, buf, nbytes);
        return Rf_ScalarReal(REAL(offset)[0] + (double)nbytes);
}

/* The length of the NUL-terminated string at offset, or a failure. */
SEXP
nw_memory_strlen(SEXP instptr, SEXP memidx, SEXP offset)
{
        struct meminst *mi = get_memory(instptr, memidx, NULL);
        uint64_t size = memory_bytes(mi);
        double off = REAL(offset)[0];
        if (!(off >= 0) || off >= (double)size) {
                return fail_bounds(off >= 0 ? (uint64_t)off : 0, 1, size);
        }
        /* Bytes beyond the allocated part are zero: toywasm allocates
           lazily and zero-fills. */
        uint64_t start = (uint64_t)off;
        uint64_t alloc = mi->allocated < size ? mi->allocated : size;
        for (uint64_t i = start; i < alloc; i++) {
                if (mi->data[i] == 0) {
                        return Rf_ScalarReal((double)(i - start));
                }
        }
        if (alloc < size) {
                return Rf_ScalarReal((double)(start > alloc ? 0 : alloc - start));
        }
        return nw_fail2("nanowasm_out_of_bounds", "nanowasm_argument_error",
                        "No NUL terminator before the end of the memory.");
}
