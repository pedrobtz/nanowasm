/*
 * Failures as data.
 *
 * A C entry point that fails returns a list with class "nanowasm_failure":
 * `class` (the condition classes, most specific first, without the common
 * "nanowasm_error" / "error" / "condition" tail), `message`, and `fields`,
 * a named list of extra condition fields. R's nw_check() turns it into a
 * condition. Building the condition in R keeps every longjmp out of C code
 * that may still hold toywasm state, and keeps the class tree in one place.
 */
#include <errno.h>
#include <string.h>

#include "nanowasm.h"

static SEXP
make_failure(SEXP classes, const char *msg, SEXP fields)
{
        PROTECT(classes);
        PROTECT(fields);
        SEXP res = PROTECT(Rf_allocVector(VECSXP, 3));
        SEXP names = PROTECT(Rf_allocVector(STRSXP, 3));
        SET_VECTOR_ELT(res, 0, classes);
        SET_VECTOR_ELT(res, 1, Rf_mkString(msg));
        SET_VECTOR_ELT(res, 2, fields);
        SET_STRING_ELT(names, 0, Rf_mkChar("class"));
        SET_STRING_ELT(names, 1, Rf_mkChar("message"));
        SET_STRING_ELT(names, 2, Rf_mkChar("fields"));
        Rf_setAttrib(res, R_NamesSymbol, names);
        Rf_setAttrib(res, R_ClassSymbol, Rf_mkString("nanowasm_failure"));
        UNPROTECT(4);
        return res;
}

SEXP
nw_fail(const char *cls, const char *msg)
{
        return make_failure(Rf_mkString(cls), msg,
                            Rf_allocVector(VECSXP, 0));
}

SEXP
nw_fail2(const char *cls, const char *parent, const char *msg)
{
        SEXP classes = PROTECT(Rf_allocVector(STRSXP, 2));
        SET_STRING_ELT(classes, 0, Rf_mkChar(cls));
        SET_STRING_ELT(classes, 1, Rf_mkChar(parent));
        SEXP res = make_failure(classes, msg, Rf_allocVector(VECSXP, 0));
        UNPROTECT(1);
        return res;
}

/*
 * toywasm's trap ids, mapped to a stable lower-snake `trap_id`, the message
 * shown to users (worded as in the WebAssembly spec tests where one exists),
 * and an optional subclass of nanowasm_trap.
 */
struct trap_desc {
        const char *id;
        const char *message;
        const char *subclass;
};

static struct trap_desc
describe_trap(enum trapid id)
{
        static const char *const oob = "nanowasm_out_of_bounds";
        static const char *const stack = "nanowasm_stack_exhausted";
        struct trap_desc d = {"misc", "trap", NULL};
        switch (id) {
        case TRAP_MISC:
                break;
        case TRAP_DIV_BY_ZERO:
                d = (struct trap_desc){"div_by_zero",
                                       "integer divide by zero", NULL};
                break;
        case TRAP_INTEGER_OVERFLOW:
                d = (struct trap_desc){"integer_overflow", "integer overflow",
                                       NULL};
                break;
        case TRAP_OUT_OF_BOUNDS_MEMORY_ACCESS:
                d = (struct trap_desc){"out_of_bounds_memory_access",
                                       "out of bounds memory access", oob};
                break;
        case TRAP_UNREACHABLE:
                d = (struct trap_desc){"unreachable", "unreachable executed",
                                       NULL};
                break;
        case TRAP_TOO_MANY_FRAMES:
                d = (struct trap_desc){"too_many_frames",
                                       "call stack exhausted", stack};
                break;
        case TRAP_TOO_MANY_STACKCELLS:
                d = (struct trap_desc){"too_many_stackcells",
                                       "value stack exhausted", stack};
                break;
        case TRAP_CALL_INDIRECT_OUT_OF_BOUNDS_TABLE_ACCESS:
                d = (struct trap_desc){
                        "call_indirect_out_of_bounds_table_access",
                        "undefined element", oob};
                break;
        case TRAP_CALL_INDIRECT_NULL_FUNCREF:
                d = (struct trap_desc){"call_indirect_null_funcref",
                                       "uninitialized element", NULL};
                break;
        case TRAP_CALL_INDIRECT_FUNCTYPE_MISMATCH:
                d = (struct trap_desc){"call_indirect_functype_mismatch",
                                       "indirect call type mismatch", NULL};
                break;
        case TRAP_INVALID_CONVERSION_TO_INTEGER:
                d = (struct trap_desc){"invalid_conversion_to_integer",
                                       "invalid conversion to integer", NULL};
                break;
        case TRAP_VOLUNTARY_EXIT:
                d = (struct trap_desc){"voluntary_exit", "exit", NULL};
                break;
        case TRAP_VOLUNTARY_THREAD_EXIT:
                d = (struct trap_desc){"voluntary_thread_exit", "thread exit",
                                       NULL};
                break;
        case TRAP_OUT_OF_BOUNDS_DATA_ACCESS:
                d = (struct trap_desc){"out_of_bounds_data_access",
                                       "out of bounds memory access", oob};
                break;
        case TRAP_OUT_OF_BOUNDS_TABLE_ACCESS:
                d = (struct trap_desc){"out_of_bounds_table_access",
                                       "out of bounds table access", oob};
                break;
        case TRAP_OUT_OF_BOUNDS_ELEMENT_ACCESS:
                d = (struct trap_desc){"out_of_bounds_element_access",
                                       "out of bounds table access", oob};
                break;
        case TRAP_ATOMIC_WAIT_ON_NON_SHARED_MEMORY:
                d = (struct trap_desc){"atomic_wait_on_non_shared_memory",
                                       "atomic wait on non-shared memory",
                                       NULL};
                break;
        case TRAP_UNALIGNED_ATOMIC_OPERATION:
                d = (struct trap_desc){"unaligned_atomic_operation",
                                       "unaligned atomic", NULL};
                break;
        case TRAP_UNALIGNED_MEMORY_ACCESS:
                d = (struct trap_desc){"unaligned_memory_access",
                                       "unaligned memory access", NULL};
                break;
        case TRAP_INDIRECT_FUNCTION_TABLE_NOT_FOUND:
                d = (struct trap_desc){"indirect_function_table_not_found",
                                       "indirect function table not found",
                                       NULL};
                break;
        case TRAP_UNCAUGHT_EXCEPTION:
                d = (struct trap_desc){"uncaught_exception",
                                       "uncaught exception", NULL};
                break;
        case TRAP_THROW_REF_NULL:
                d = (struct trap_desc){"throw_ref_null", "null exception reference",
                                       NULL};
                break;
        case TRAP_UNRESOLVED_IMPORTED_FUNC:
                d = (struct trap_desc){"unresolved_imported_func",
                                       "unresolved imported function", NULL};
                break;
        case TRAP_MEMORY_NOT_FOUND:
                d = (struct trap_desc){"memory_not_found", "memory not found",
                                       NULL};
                break;
        }
        return d;
}

SEXP
nw_fail_trap(const struct trap_info *trap, const char *detail)
{
        struct trap_desc d = describe_trap(trap->trapid);
        int n = d.subclass != NULL ? 2 : 1;
        SEXP classes = PROTECT(Rf_allocVector(STRSXP, n));
        if (d.subclass != NULL) {
                SET_STRING_ELT(classes, 0, Rf_mkChar(d.subclass));
        }
        SET_STRING_ELT(classes, n - 1, Rf_mkChar("nanowasm_trap"));

        SEXP fields = PROTECT(Rf_allocVector(VECSXP, 2));
        SEXP names = PROTECT(Rf_allocVector(STRSXP, 2));
        SET_VECTOR_ELT(fields, 0, Rf_mkString(d.id));
        SET_VECTOR_ELT(fields, 1, Rf_mkString(detail != NULL ? detail : ""));
        SET_STRING_ELT(names, 0, Rf_mkChar("trap_id"));
        SET_STRING_ELT(names, 1, Rf_mkChar("detail"));
        Rf_setAttrib(fields, R_NamesSymbol, names);

        char msg[256];
        snprintf(msg, sizeof(msg), "WebAssembly trap: %s.", d.message);
        SEXP res = make_failure(classes, msg, fields);
        UNPROTECT(3);
        return res;
}

/* A toywasm error code that is not a trap. */
SEXP
nw_fail_errno(int err, const char *what)
{
        char msg[512];
        if (err == ENOMEM) {
                snprintf(msg, sizeof(msg), "%s: out of memory.", what);
                return nw_fail("nanowasm_memory_limit", msg);
        }
        snprintf(msg, sizeof(msg), "%s: %s (error %d).", what, strerror(err),
                 err);
        return nw_fail("nanowasm_runtime_error", msg);
}
