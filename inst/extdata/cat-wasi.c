/* Copies the files named by its arguments (or stdin) to stdout. Reports
   files it can't open on stderr and exits with status 1. */
#include <errno.h>
#include <stdio.h>
#include <string.h>

static void copy(FILE *in) {
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
        fwrite(buf, 1, n, stdout);
    }
}

int main(int argc, char **argv) {
    int status = 0;
    if (argc < 2) {
        copy(stdin);
    }
    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        if (f == NULL) {
            fprintf(stderr, "cat: %s: %s\n", argv[i], strerror(errno));
            status = 1;
            continue;
        }
        copy(f);
        fclose(f);
    }
    return status;
}
