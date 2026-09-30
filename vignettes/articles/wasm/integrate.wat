;; The trapezoidal rule for an imported function f over [a, b].
(module
  (import "math" "f" (func $f (param f64) (result f64)))

  (func (export "trapezoid") (param $a f64) (param $b f64) (param $n i32)
    (result f64)
    (local $h f64)
    (local $sum f64)
    (local $i i32)
    (local.set $h
      (f64.div (f64.sub (local.get $b) (local.get $a))
               (f64.convert_i32_u (local.get $n))))
    (local.set $sum
      (f64.mul (f64.const 0.5)
               (f64.add (call $f (local.get $a)) (call $f (local.get $b)))))
    (local.set $i (i32.const 1))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $sum
          (f64.add (local.get $sum)
            (call $f
              (f64.add (local.get $a)
                       (f64.mul (f64.convert_i32_u (local.get $i))
                                (local.get $h))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (f64.mul (local.get $sum) (local.get $h))))
