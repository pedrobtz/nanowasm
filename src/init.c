#include <R_ext/Rdynload.h>

#include "nanowasm.h"

static const R_CallMethodDef call_methods[] = {
        {"nw_toywasm_version", (DL_FUNC)&nw_toywasm_version, 0},
        {NULL, NULL, 0}
};

void
R_init_nanowasm(DllInfo *dll)
{
        R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
        R_useDynamicSymbols(dll, FALSE);
        R_forceSymbols(dll, TRUE);
}
