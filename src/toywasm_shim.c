/*
 * Replacements for toywasm's xlog.c and nbio.c, which are not vendored.
 *
 * Upstream writes diagnostics and statistics straight to stdout and stderr.
 * R CMD check rejects compiled code that does, and nanowasm reports errors
 * through toywasm's `struct report` instead, so everything written here is
 * discarded.
 */
#include <stdarg.h>
#include <stdio.h>

#include "toywasm/nbio.h"
#include "toywasm/xlog.h"

void
xlog_printf(const char *fmt, ...)
{
        (void)fmt;
}

void
xlog_printf_raw(const char *fmt, ...)
{
        (void)fmt;
}

void
xlog__trace(const char *fmt, ...)
{
        (void)fmt;
}

void
xlog_error(const char *fmt, ...)
{
        (void)fmt;
}

int
nbio_vfprintf(FILE *fp, const char *fmt, va_list ap)
{
        (void)fp;
        (void)fmt;
        (void)ap;
        return 0;
}

int
nbio_fprintf(FILE *fp, const char *fmt, ...)
{
        (void)fp;
        (void)fmt;
        return 0;
}

int
nbio_printf(const char *fmt, ...)
{
        (void)fmt;
        return 0;
}
