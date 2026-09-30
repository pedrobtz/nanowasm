;; A start function that runs at instantiation.
(module
  (global $g (mut i32) (i32.const 0))
  (func $start i32.const 7 global.set $g)
  (start $start)
  (func (export "get") (result i32) global.get $g))
