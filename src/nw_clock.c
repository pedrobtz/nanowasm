/*
 * A monotonic clock for timeouts, in seconds from an arbitrary origin.
 *
 * Kept apart from the rest of the glue because <windows.h> and R's headers
 * don't mix (both define ERROR, among others).
 */
#if defined(_WIN32)
#include <windows.h>
#else
#define _POSIX_C_SOURCE 200809L
#include <time.h>
#endif

double nw_clock(void);

double
nw_clock(void)
{
#if defined(_WIN32)
        LARGE_INTEGER freq, count;
        QueryPerformanceFrequency(&freq);
        QueryPerformanceCounter(&count);
        return (double)count.QuadPart / (double)freq.QuadPart;
#else
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
#endif
}
