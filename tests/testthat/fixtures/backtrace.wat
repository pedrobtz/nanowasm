;; wat2wasm: --debug-names
;; Internal functions with names in the name section, called through a
;; chain so a trap has a backtrace.
(module
  (import "env" "check" (func $check (param i32)))
  (func $inner (param $x i32) (result i32)
    (i32.div_s (i32.const 100) (local.get $x)))
  (func $middle (param $x i32) (result i32)
    (i32.add (call $inner (local.get $x)) (i32.const 1)))
  (func $outer (export "run") (param $x i32) (result i32)
    (call $middle (local.get $x)))
  (func $report (export "report") (param $x i32)
    (call $check (local.get $x)))
  (func $deep (export "deep") (param $n i32) (result i32)
    (if (result i32) (i32.eqz (local.get $n))
      (then (unreachable))
      (else (call $deep (i32.sub (local.get $n) (i32.const 1)))))))
