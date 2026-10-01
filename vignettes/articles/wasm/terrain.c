// wasi-sdk: -mexec-model=reactor
/* Terrain analysis on an elevation grid, as a library: R passes a
   column-major matrix through linear memory and gets one back.

   Built as a WASI reactor (no main), exporting its own allocator so R can
   ask for space in the module's memory. */
#include <math.h>
#include <stdlib.h>

#define EXPORT(name) __attribute__((export_name(name)))

EXPORT("alloc") void *alloc(int bytes) { return malloc((size_t)bytes); }
EXPORT("release") void release(void *p) { free(p); }

/* Elevation at row i, column j of an nr x nc column-major matrix, with the
   edges extended outwards. */
static double at(const double *z, int nr, int nc, int i, int j) {
    if (i < 0) i = 0;
    if (i >= nr) i = nr - 1;
    if (j < 0) j = 0;
    if (j >= nc) j = nc - 1;
    return z[i + j * nr];
}

/* Horn's method: the surface's slopes at a cell, along x (rows of the
   matrix, as image() draws them) and y (columns, pointing north). */
static void gradient(const double *z, int nr, int nc, int i, int j,
                     double cell, double *dx, double *dy) {
    *dx = ((at(z, nr, nc, i + 1, j - 1) + 2 * at(z, nr, nc, i + 1, j) +
            at(z, nr, nc, i + 1, j + 1)) -
           (at(z, nr, nc, i - 1, j - 1) + 2 * at(z, nr, nc, i - 1, j) +
            at(z, nr, nc, i - 1, j + 1))) / (8 * cell);
    *dy = ((at(z, nr, nc, i - 1, j + 1) + 2 * at(z, nr, nc, i, j + 1) +
            at(z, nr, nc, i + 1, j + 1)) -
           (at(z, nr, nc, i - 1, j - 1) + 2 * at(z, nr, nc, i, j - 1) +
            at(z, nr, nc, i + 1, j - 1))) / (8 * cell);
}

/* Slope in degrees. */
EXPORT("slope")
void slope(const double *z, double *out, int nr, int nc, double cell) {
    for (int j = 0; j < nc; j++) {
        for (int i = 0; i < nr; i++) {
            double dx, dy;
            gradient(z, nr, nc, i, j, cell, &dx, &dy);
            out[i + j * nr] = atan(sqrt(dx * dx + dy * dy)) * 180 / M_PI;
        }
    }
}

/* Hillshade: brightness (0-1) of the surface lit from a compass azimuth
   (clockwise from north) and an altitude above the horizon, in degrees.
   It is the cosine between the surface normal and the light. */
EXPORT("hillshade")
void hillshade(const double *z, double *out, int nr, int nc, double cell,
               double azimuth, double altitude) {
    double az = (90 - azimuth) * M_PI / 180, alt = altitude * M_PI / 180;
    double lx = cos(alt) * cos(az), ly = cos(alt) * sin(az), lz = sin(alt);
    for (int j = 0; j < nc; j++) {
        for (int i = 0; i < nr; i++) {
            double dx, dy;
            gradient(z, nr, nc, i, j, cell, &dx, &dy);
            double v = (-dx * lx - dy * ly + lz) / sqrt(dx * dx + dy * dy + 1);
            out[i + j * nr] = v < 0 ? 0 : v;
        }
    }
}
