;; wat2wasm: --enable-multi-memory
;; Two exported memories (multi-memory), so wasm_memory() must be told which.
(module
  (memory (export "a") 1)
  (memory (export "b") 2))
