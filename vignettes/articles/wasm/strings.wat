;; Byte-level string helpers working in linear memory.
(module
  (memory (export "memory") 1)

  ;; Upper-case the ASCII letters in len bytes at ptr, in place.
  (func (export "upper") (param $ptr i32) (param $len i32)
    (local $end i32)
    (local $c i32)
    (local.set $end (i32.add (local.get $ptr) (local.get $len)))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $ptr) (local.get $end)))
        (local.set $c (i32.load8_u (local.get $ptr)))
        (if (i32.and (i32.ge_u (local.get $c) (i32.const 97))
                     (i32.le_u (local.get $c) (i32.const 122)))
          (then (i32.store8 (local.get $ptr)
                            (i32.sub (local.get $c) (i32.const 32)))))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (br $next))))

  ;; How many of the len bytes at ptr equal b.
  (func (export "count") (param $ptr i32) (param $len i32) (param $b i32)
    (result i32)
    (local $end i32)
    (local $n i32)
    (local.set $end (i32.add (local.get $ptr) (local.get $len)))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $ptr) (local.get $end)))
        (if (i32.eq (i32.load8_u (local.get $ptr)) (local.get $b))
          (then (local.set $n (i32.add (local.get $n) (i32.const 1)))))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 1)))
        (br $next)))
    (local.get $n)))
