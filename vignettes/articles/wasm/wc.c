/* A small wc: lines, words and bytes of each file named (or of stdin),
   plus a total line when there is more than one file. */
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

struct counts { long lines, words, bytes; };

static struct counts count(FILE *in) {
    struct counts c = {0, 0, 0};
    int ch, in_word = 0;
    while ((ch = getc(in)) != EOF) {
        c.bytes++;
        if (ch == '\n') c.lines++;
        if (isspace(ch)) in_word = 0;
        else if (!in_word) { in_word = 1; c.words++; }
    }
    return c;
}

static void show(struct counts c, const char *name) {
    printf("%7ld %7ld %7ld %s\n", c.lines, c.words, c.bytes, name);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        show(count(stdin), "");
        return 0;
    }
    struct counts total = {0, 0, 0};
    int status = 0;
    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "r");
        if (f == NULL) {
            fprintf(stderr, "wc: %s: %s\n", argv[i], strerror(errno));
            status = 1;
            continue;
        }
        struct counts c = count(f);
        fclose(f);
        show(c, argv[i]);
        total.lines += c.lines;
        total.words += c.words;
        total.bytes += c.bytes;
    }
    if (argc > 2) show(total, "total");
    return status;
}
