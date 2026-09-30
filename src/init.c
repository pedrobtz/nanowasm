#include <R_ext/Rdynload.h>

#include "nanowasm.h"

#define CALLDEF(name, n) {#name, (DL_FUNC)&name, n}

static const R_CallMethodDef call_methods[] = {
        CALLDEF(nw_toywasm_version, 0),
        CALLDEF(nw_ptr_is_live, 1),
        CALLDEF(nw_module_load, 1),
        CALLDEF(nw_module_exports, 1),
        CALLDEF(nw_module_imports, 1),
        CALLDEF(nw_instantiate, 2),
        CALLDEF(nw_call, 3),
        CALLDEF(nw_global_get, 2),
        CALLDEF(nw_global_set, 3),
        CALLDEF(nw_memory_index, 2),
        CALLDEF(nw_memory_size, 2),
        CALLDEF(nw_memory_grow, 3),
        CALLDEF(nw_memory_read, 5),
        CALLDEF(nw_memory_write, 5),
        CALLDEF(nw_memory_strlen, 3),
        {NULL, NULL, 0}
};

void
R_init_nanowasm(DllInfo *dll)
{
        R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
        R_useDynamicSymbols(dll, FALSE);
        R_forceSymbols(dll, TRUE);
}
