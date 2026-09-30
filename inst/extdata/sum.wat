;; A bump allocator and a function that sums doubles in memory.
(module
  (memory (export "memory") 1)
  (global $heap_top (export "heap_top") (mut i32) (i32.const 1024))

  ;; Reserve n bytes, 8-byte aligned, growing the memory if needed.
  ;; Returns the offset of the block, or 0 if memory can't grow.
  (func (export "alloc") (param $n i32) (result i32)
    (local $ptr i32)
    (local $end i32)
    (local.set $ptr
      (i32.and (i32.add (global.get $heap_top) (i32.const 7)) (i32.const -8)))
    (local.set $end (i32.add (local.get $ptr) (local.get $n)))
    (block $fits
      (loop $grow
        (br_if $fits
          (i32.le_u (local.get $end) (i32.mul (memory.size) (i32.const 65536))))
        (if (i32.eq (memory.grow (i32.const 1)) (i32.const -1))
          (then (return (i32.const 0))))
        (br $grow)))
    (global.set $heap_top (local.get $end))
    (local.get $ptr))

  ;; Sum n doubles starting at ptr.
  (func (export "sum_f64") (param $ptr i32) (param $n i32) (result f64)
    (local $acc f64)
    (block $done
      (loop $next
        (br_if $done (i32.eqz (local.get $n)))
        (local.set $acc (f64.add (local.get $acc) (f64.load (local.get $ptr))))
        (local.set $ptr (i32.add (local.get $ptr) (i32.const 8)))
        (local.set $n (i32.sub (local.get $n) (i32.const 1)))
        (br $next)))
    (local.get $acc)))
