# wasm_func() validates and prints

    Code
      print(f)
    Output
      <nanowasm_func> (i32, i32) -> i32

---

    Code
      print(wasm_func(function() NULL, results = c("i64", "f64")))
    Output
      <nanowasm_func> () -> (i64, f64)

# the caller gives access to the calling instance's memory

    Code
      print(kept)
    Output
      <nanowasm_caller> (no longer valid)

