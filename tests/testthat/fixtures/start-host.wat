;; A start function that calls an import.
(module
  (import "env" "init" (func $init (result i32)))
  (global $g (mut i32) (i32.const 0))
  (func $start (global.set $g (call $init)))
  (start $start)
  (func (export "get") (result i32) (global.get $g)))
