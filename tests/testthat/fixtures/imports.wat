;; A module that needs one import of every kind.
(module
  (import "env" "log" (func (param i32)))
  (import "env" "mem" (memory 1))
  (import "js" "g" (global i32))
  (import "js" "tbl" (table 1 funcref))
  (func (export "f")))
