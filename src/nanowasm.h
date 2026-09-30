#ifndef NANOWASM_H
#define NANOWASM_H

#include <stddef.h>
#include <stdint.h>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include "toywasm/exec_context.h"
/* host_instance.h has no include guard: include it here, and only here. */
#include "toywasm/host_instance.h"
#include "toywasm/mem.h"
#include "toywasm/type.h"

/*
 * Objects shared with R through external pointers.
 *
 * R may finalise a module and an instance made from it in the same garbage
 * collection, in either order, so the prot chain alone cannot keep a module
 * alive for as long as its instances need it. Each object is reference
 * counted instead: the external pointer holds one reference, every instance
 * holds one on its module, and the memory is freed when the last is dropped.
 */
struct nw_module {
        int refs;
        struct mem_context mctx;
        struct module *module; /* NULL if loading failed */
        uint8_t *bytes;        /* toywasm runs the binary in place */
        size_t nbytes;
};

struct nw_host_binding;

struct nw_instance {
        int refs;
        struct nw_module *mod;
        struct mem_context mctx; /* its limit is the instance memory limit */
        struct instance *inst;   /* NULL until instantiation succeeds */
        struct exec_options options;
        double timeout; /* seconds per call; <= 0 or infinite: none */
        bool busy;      /* running; toywasm instances are not re-entrant */

        /* Imports (nw_host.c). */
        SEXP self; /* this instance's external pointer; not protected, only
                      used while a call keeps it alive */
        struct import_object *imports;
        struct nw_host_binding *bindings;
        uint32_t nbindings;
        SEXP host_failure; /* preserved; set by a failed host call */
        bool unwinding;    /* an R jump is waiting to be resumed */
};

/* One imported R function. hi must stay first: toywasm hands the
   trampoline &hi, and the trampoline casts it back. */
struct nw_host_binding {
        struct host_instance hi;
        struct funcinst fi;
        SEXP fn; /* the R wrapper; protected by the instance's prot */
        const struct import *im;
        struct nw_instance *owner;
};

/* nw_failure.c: failures travel back to R as data and are signalled there,
   so no R longjmp ever leaves C code that still holds toywasm state. */
SEXP nw_fail(const char *cls, const char *msg);
SEXP nw_fail2(const char *cls, const char *parent, const char *msg);
SEXP nw_fail_trap(const struct trap_info *trap, const char *detail);
SEXP nw_fail_errno(int err, const char *what);
SEXP nw_fail_timeout(double elapsed, double limit);
SEXP nw_fail_interrupt(void);

/* nw_module.c */
struct nw_module *nw_module_get(SEXP ptr);
void nw_module_release(struct nw_module *nm);
const char *nw_valtype_name(enum valtype t);
SEXP nw_module_load(SEXP bytes);
SEXP nw_module_exports(SEXP ptr);
SEXP nw_module_imports(SEXP ptr);
SEXP nw_ptr_is_live(SEXP ptr);

/* nw_instance.c */
#define NW_ARG_VALUE (-1)
#define NW_ARG_RESULT (-2) /* result k (0-based) is NW_ARG_RESULT - k */
struct nw_instance *nw_instance_get(SEXP ptr);
bool nw_is_supported(enum valtype t);
SEXP nw_arg_to_val(SEXP x, enum valtype t, const char *func, R_xlen_t i,
                   struct val *v);
SEXP nw_val_to_sexp(const struct val *v, enum valtype t);
SEXP nw_instantiate(SEXP modptr, SEXP limits, SEXP funcs);
SEXP nw_call(SEXP instptr, SEXP name, SEXP args);
SEXP nw_global_get(SEXP instptr, SEXP name);
SEXP nw_global_set(SEXP instptr, SEXP name, SEXP value);

/* nw_memory.c */
SEXP nw_memory_index(SEXP instptr, SEXP name);
SEXP nw_memory_size(SEXP instptr, SEXP memidx);
SEXP nw_memory_grow(SEXP instptr, SEXP memidx, SEXP pages);
SEXP nw_memory_read(SEXP instptr, SEXP memidx, SEXP offset, SEXP n,
                    SEXP type);
SEXP nw_memory_write(SEXP instptr, SEXP memidx, SEXP offset, SEXP x,
                     SEXP type);
SEXP nw_memory_strlen(SEXP instptr, SEXP memidx, SEXP offset);

/* nw_host.c */
void nw_host_init(void);
int nw_host_bind(struct nw_instance *ni, SEXP funcs);
void nw_host_release(struct nw_instance *ni);
SEXP nw_finish_run(struct nw_instance *ni);

/* nw_clock.c */
double nw_clock(void);

/* info.c */
SEXP nw_toywasm_version(void);

#endif /* NANOWASM_H */
