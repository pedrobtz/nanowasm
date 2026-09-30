;; Modules that try to run forever or eat all memory.
(module
  (memory (export "memory") 1)
  (table $t 1 funcref)

  ;; Never returns.
  (func (export "spin") (loop $l (br $l)))

  ;; Grows the memory one page at a time until memory.grow fails, and
  ;; returns the number of pages added.
  (func (export "grow_until_fail") (result i32)
    (local $n i32)
    (block $done
      (loop $l
        (br_if $done (i32.eq (memory.grow (i32.const 1)) (i32.const -1)))
        (local.set $n (i32.add (local.get $n) (i32.const 1)))
        (br $l)))
    (local.get $n))

  ;; Grows the memory by n pages and writes its last byte, which forces
  ;; the (lazily allocated) memory to exist. Returns the new size in pages,
  ;; or -1 if growing failed.
  (func (export "grow_and_touch") (param $n i32) (result i32)
    (if (i32.eq (memory.grow (local.get $n)) (i32.const -1))
      (then (return (i32.const -1))))
    (i32.store8
      (i32.sub (i32.mul (memory.size) (i32.const 65536)) (i32.const 1))
      (i32.const 1))
    (memory.size))

  ;; Grows the table by n elements; -1 if that fails.
  (func (export "table_grow") (param $n i32) (result i32)
    (table.grow $t (ref.null func) (local.get $n))))
