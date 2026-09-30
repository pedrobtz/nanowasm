;; Imports of several shapes, each with an export that calls it.
(module
  (import "env" "add" (func $add (param i32 i32) (result i32)))
  (import "env" "pair" (func $pair (result i64 f64)))
  (import "env" "effect" (func $effect))
  (import "math" "twice" (func $twice (param i64) (result i64)))
  (memory (export "memory") 1)
  (data (i32.const 0) "hi")
  (func (export "call_add") (param i32 i32) (result i32)
    (call $add (local.get 0) (local.get 1)))
  (func (export "call_pair") (result i64 f64) (call $pair))
  (func (export "call_effect") (call $effect))
  (func (export "call_twice") (param i64) (result i64)
    (call $twice (local.get 0)))
  ;; Passes 2^60, which a double can't hold exactly, to the import.
  (func (export "twice_big") (result i64)
    (call $twice (i64.const 1152921504606846976)))
  ;; Sums n + (n - 1) + ... + 1 through the imported add.
  (func (export "sum_adds") (param $n i32) (result i32)
    (local $acc i32)
    (block $done
      (loop $l
        (br_if $done (i32.eqz (local.get $n)))
        (local.set $acc (call $add (local.get $acc) (local.get $n)))
        (local.set $n (i32.sub (local.get $n) (i32.const 1)))
        (br $l)))
    (local.get $acc))
  ;; The import runs, then the module traps.
  (func (export "effect_then_trap") (call $effect) unreachable))
