;; Renders the Mandelbrot set: one byte per pixel, the number of
;; iterations before the point escaped (at most maxiter, <= 255).
(module
  (memory (export "memory") 4)

  (func (export "render")
    (param $ptr i32) (param $w i32) (param $h i32)
    (param $x0 f64) (param $y0 f64) (param $x1 f64) (param $y1 f64)
    (param $maxiter i32)
    (local $x i32) (local $y i32) (local $i i32)
    (local $cr f64) (local $ci f64) (local $zr f64) (local $zi f64)
    (local $t f64)
    (loop $rows
      (local.set $ci
        (f64.add (local.get $y0)
          (f64.div
            (f64.mul (f64.sub (local.get $y1) (local.get $y0))
                     (f64.convert_i32_u (local.get $y)))
            (f64.convert_i32_u (local.get $h)))))
      (local.set $x (i32.const 0))
      (loop $cols
        (local.set $cr
          (f64.add (local.get $x0)
            (f64.div
              (f64.mul (f64.sub (local.get $x1) (local.get $x0))
                       (f64.convert_i32_u (local.get $x)))
              (f64.convert_i32_u (local.get $w)))))
        (local.set $zr (f64.const 0))
        (local.set $zi (f64.const 0))
        (local.set $i (i32.const 0))
        (block $escaped
          (loop $iterate
            (br_if $escaped (i32.ge_u (local.get $i) (local.get $maxiter)))
            (br_if $escaped
              (f64.gt
                (f64.add (f64.mul (local.get $zr) (local.get $zr))
                         (f64.mul (local.get $zi) (local.get $zi)))
                (f64.const 4)))
            (local.set $t
              (f64.add
                (f64.sub (f64.mul (local.get $zr) (local.get $zr))
                         (f64.mul (local.get $zi) (local.get $zi)))
                (local.get $cr)))
            (local.set $zi
              (f64.add
                (f64.mul (f64.mul (f64.const 2) (local.get $zr))
                         (local.get $zi))
                (local.get $ci)))
            (local.set $zr (local.get $t))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $iterate)))
        (i32.store8
          (i32.add (local.get $ptr)
                   (i32.add (i32.mul (local.get $y) (local.get $w))
                            (local.get $x)))
          (local.get $i))
        (local.set $x (i32.add (local.get $x) (i32.const 1)))
        (br_if $cols (i32.lt_u (local.get $x) (local.get $w))))
      (local.set $y (i32.add (local.get $y) (i32.const 1)))
      (br_if $rows (i32.lt_u (local.get $y) (local.get $h))))))
