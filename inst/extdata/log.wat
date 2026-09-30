;; Calls an imported log(ptr, len) with a string in its memory.
(module
  (import "env" "log" (func $log (param i32 i32)))
  (memory (export "memory") 1)
  (data (i32.const 16) "Hello from WebAssembly!")
  (func (export "greet")
    (call $log (i32.const 16) (i32.const 23))))
