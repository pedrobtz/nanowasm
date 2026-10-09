;; wat2wasm: --enable-exceptions
;; The exception-handling proposal's instructions: throw, try_table with
;; catch, catch_all and catch_ref, and throw_ref.
(module
  (tag $oops (export "oops") (param i32))
  (tag $other (param f64))

  (func $thrower (param $x i32) (throw $oops (local.get $x)))

  ;; Throws $oops with x unless x is 0, catches it and returns its payload;
  ;; -1 if nothing was thrown.
  (func (export "catch_it") (param $x i32) (result i32)
    (block $handler (result i32)
      (try_table (catch $oops $handler)
        (if (local.get $x) (then (call $thrower (local.get $x)))))
      (i32.const -1)))

  ;; catch_all catches an exception of any tag.
  (func (export "catch_all") (result i32)
    (block $any
      (try_table (catch_all $any)
        (throw $other (f64.const 1.5)))
      (return (i32.const 0)))
    (i32.const 99))

  ;; Catches with catch_ref and rethrows with throw_ref to an outer handler.
  (func (export "rethrow") (param $x i32) (result i32)
    (local $e exnref)
    (block $outer (result i32)
      (try_table (result i32) (catch $oops $outer)
        (block $inner (result i32 exnref)
          (try_table (catch_ref $oops $inner)
            (call $thrower (local.get $x)))
          (unreachable))
        (local.set $e)
        (drop)
        (throw_ref (local.get $e)))))

  ;; Nothing catches it.
  (func (export "uncaught") (param $x i32) (call $thrower (local.get $x))))
