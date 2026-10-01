// wasi-sdk: -fwasm-exceptions -mllvm -wasm-use-legacy-eh=false -lunwind
/* C++ exceptions: standard and custom types, destructors run during
   unwinding, rethrow, and (with the argument "uncaught") an exception
   nothing catches, which ends in std::terminate(). */
#include <cstdio>
#include <cstring>
#include <stdexcept>

struct Guard {
    const char *name;
    ~Guard() { std::printf("unwound %s\n", name); }
};

struct Problem {
    int code;
};

static void fail(int code) {
    Guard g{"fail"};
    if (code < 0) throw std::invalid_argument("negative");
    throw Problem{code};
}

int main(int argc, char **argv) {
    if (argc > 1 && std::strcmp(argv[1], "uncaught") == 0) {
        fail(1);
    }
    try {
        fail(-1);
    } catch (const std::exception &e) {
        std::printf("caught std::exception: %s\n", e.what());
    }
    try {
        try {
            fail(7);
        } catch (const Problem &) {
            std::printf("rethrowing\n");
            throw;
        }
    } catch (const Problem &p) {
        std::printf("caught Problem %d\n", p.code);
    }
    return 0;
}
