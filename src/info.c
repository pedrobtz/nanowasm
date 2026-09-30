#include "nanowasm.h"

#include "toywasm/toywasm_version.h"

SEXP
nw_toywasm_version(void)
{
        return Rf_mkString(TOYWASM_VERSION);
}
