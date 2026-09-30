;; Linear memory with known contents.
(module
  (memory (export "memory") 1 4)
  (data (i32.const 16) "hello\00world\00")
  (data (i32.const 64) "\ff\fe\fd\00")
  (func (export "load_i32") (param i32) (result i32) (i32.load (local.get 0)))
  (func (export "load_f64") (param i32) (result f64) (f64.load (local.get 0)))
  (func (export "grow") (param i32) (result i32) (memory.grow (local.get 0))))
