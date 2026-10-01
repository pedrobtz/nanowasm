;; The same call chain without a name section: internal functions have
;; only indices.
(module
  (func (param i32) (result i32) (i32.div_s (i32.const 100) (local.get 0)))
  (func (param i32) (result i32) (i32.add (call 0 (local.get 0)) (i32.const 1)))
  (func (export "run") (param i32) (result i32) (call 1 (local.get 0))))
