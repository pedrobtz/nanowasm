/* Reports the realtime clock, sleeps 50 ms on the monotonic clock, and
   prints 8 random bytes. */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(void) {
    struct timespec a, b, res;
    clock_gettime(CLOCK_REALTIME, &a);
    printf("realtime %lld\n", (long long)a.tv_sec);
    clock_getres(CLOCK_MONOTONIC, &res);
    printf("resolution %ld\n", res.tv_nsec);
    clock_gettime(CLOCK_MONOTONIC, &a);
    struct timespec nap = {0, 50 * 1000 * 1000};
    nanosleep(&nap, NULL);
    clock_gettime(CLOCK_MONOTONIC, &b);
    long long ms = (b.tv_sec - a.tv_sec) * 1000LL + (b.tv_nsec - a.tv_nsec) / 1000000;
    printf("slept %lld\n", ms);
    unsigned char bytes[8];
    arc4random_buf(bytes, sizeof(bytes));
    printf("random");
    for (int i = 0; i < 8; i++) printf(" %02x", bytes[i]);
    printf("\n");
    return 0;
}
