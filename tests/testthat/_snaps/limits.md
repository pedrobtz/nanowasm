# wasm_limits() validates and prints

    Code
      print(wasm_limits())
    Output
      <nanowasm_limits>
        memory:  256 MiB
        frames:  10,000
        stack:   1,000,000 cells
        timeout: none

---

    Code
      print(wasm_limits(memory = Inf, frames = 100, stack = 5000, timeout = 1.5))
    Output
      <nanowasm_limits>
        memory:  unlimited
        frames:  100
        stack:   5,000 cells
        timeout: 1.5 s

