/* Prints argc, argv and the environment; exits with the status in argv[1]
   if there is one, through exit() so proc_exit is used. */
#include <stdio.h>
#include <stdlib.h>

extern char **environ;

int main(int argc, char **argv) {
    printf("argc=%d\n", argc);
    for (int i = 0; i < argc; i++) {
        printf("argv[%d]=%s\n", i, argv[i]);
    }
    for (char **e = environ; *e != NULL; e++) {
        printf("env %s\n", *e);
    }
    fflush(stdout);
    if (argc > 1) {
        exit(atoi(argv[1]));
    }
    return 0;
}
