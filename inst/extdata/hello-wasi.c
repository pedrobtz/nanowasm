/* Greets with $GREETING (default "Hello") and its arguments. */
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    const char *greeting = getenv("GREETING");
    printf("%s", greeting != NULL ? greeting : "Hello");
    for (int i = 1; i < argc; i++) {
        printf(" %s", argv[i]);
    }
    printf("!\n");
    return 0;
}
