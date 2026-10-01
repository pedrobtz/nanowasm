/* Runs file commands given as arguments and reports each result:
     write NAME TEXT | append NAME TEXT | read NAME | readat NAME OFFSET
     ls DIR | stat NAME | mkdir DIR | rmdir DIR | rm NAME | mv FROM TO
     truncate NAME SIZE | touch NAME SECONDS
   Failures print the errno number, which in wasi-libc is the WASI errno. */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int fail(const char *op) {
    printf("%s: errno %d\n", op, errno);
    return 1;
}

static int write_file(const char *name, const char *text, int flags) {
    int fd = open(name, O_WRONLY | O_CREAT | flags, 0644);
    if (fd < 0) return fail("open");
    ssize_t n = write(fd, text, strlen(text));
    close(fd);
    if (n < 0) return fail("write");
    printf("wrote %zd\n", n);
    return 0;
}

static int read_file(const char *name, long offset) {
    int fd = open(name, O_RDONLY);
    if (fd < 0) return fail("open");
    if (offset > 0 && lseek(fd, offset, SEEK_SET) != offset) return fail("lseek");
    char buf[256];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n < 0) return fail("read");
    buf[n] = '\0';
    printf("read \"%s\"\n", buf);
    return 0;
}

static int cmp(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

static int list(const char *dir) {
    DIR *d = opendir(dir);
    if (d == NULL) return fail("opendir");
    char *names[64];
    int n = 0;
    struct dirent *e;
    while ((e = readdir(d)) != NULL && n < 64) {
        if (strcmp(e->d_name, ".") && strcmp(e->d_name, "..")) {
            names[n++] = strdup(e->d_name);
        }
    }
    closedir(d);
    qsort(names, n, sizeof(names[0]), cmp);
    printf("ls:");
    for (int i = 0; i < n; i++) {
        printf(" %s", names[i]);
        free(names[i]);
    }
    printf("\n");
    return 0;
}

int main(int argc, char **argv) {
    int failures = 0;
    for (int i = 1; i < argc; i++) {
        const char *op = argv[i];
        const char *a = i + 1 < argc ? argv[i + 1] : "";
        const char *b = i + 2 < argc ? argv[i + 2] : "";
        struct stat st;
        if (!strcmp(op, "write")) { failures += write_file(a, b, O_TRUNC); i += 2; }
        else if (!strcmp(op, "append")) { failures += write_file(a, b, O_APPEND); i += 2; }
        else if (!strcmp(op, "read")) { failures += read_file(a, 0); i += 1; }
        else if (!strcmp(op, "readat")) { failures += read_file(a, atol(b)); i += 2; }
        else if (!strcmp(op, "ls")) { failures += list(a); i += 1; }
        else if (!strcmp(op, "stat")) {
            if (stat(a, &st) != 0) failures += fail("stat");
            else printf("stat %s %lld\n", S_ISDIR(st.st_mode) ? "dir" : "file", (long long)st.st_size);
            i += 1;
        }
        else if (!strcmp(op, "mkdir")) { if (mkdir(a, 0755) != 0) failures += fail("mkdir"); else printf("mkdir ok\n"); i += 1; }
        else if (!strcmp(op, "rmdir")) { if (rmdir(a) != 0) failures += fail("rmdir"); else printf("rmdir ok\n"); i += 1; }
        else if (!strcmp(op, "rm")) { if (unlink(a) != 0) failures += fail("rm"); else printf("rm ok\n"); i += 1; }
        else if (!strcmp(op, "mv")) { if (rename(a, b) != 0) failures += fail("mv"); else printf("mv ok\n"); i += 2; }
        else if (!strcmp(op, "touch")) {
            struct timespec times[2] = {{0, UTIME_OMIT}, {atol(b), 0}};
            if (utimensat(AT_FDCWD, a, times, 0) != 0) failures += fail("touch"); else printf("touch ok\n");
            i += 2;
        }
        else if (!strcmp(op, "truncate")) { if (truncate(a, atol(b)) != 0) failures += fail("truncate"); else printf("truncate ok\n"); i += 2; }
        else { printf("unknown command %s\n", op); return 2; }
    }
    return failures > 0;
}
