# wasm_run() runs a program and captures its output

    Code
      print(res)
    Output
      <nanowasm_run> exit status 0
      -- stdout --
      Hi from R!

# WASI environments print

    Code
      print(wasm_wasi(args = c("a", "b c"), env = c(K = "v"), stdin = "x", stdout = "capture"))
    Output
      <nanowasm_wasi>
        args:   "main" "a" "b c"
        env:    K=v
        stdin:  2 bytes
        stdout: capture, stderr: console
        dirs:   (none)

