/* Reads stdin, writes it upper-cased to stdout and its length to stderr.
   Then writes "é" (two UTF-8 bytes) in two separate writes. */
#include <ctype.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
    int c;
    long n = 0;
    while ((c = getchar()) != EOF) {
        putchar(toupper(c));
        n++;
    }
    fflush(stdout);
    fprintf(stderr, "read %ld bytes\n", n);
    write(1, "\xc3", 1);
    write(1, "\xa9\n", 2);
    return 0;
}
