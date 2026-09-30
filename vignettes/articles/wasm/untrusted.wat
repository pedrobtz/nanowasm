;; Code you would not want to run without limits.
(module
  (memory 1)

  ;; Never returns.
  (func (export "spin") (loop $forever (br $forever)))

  ;; Recurses without end.
  (func $down (export "recurse") (param i32) (result i32)
    (call $down (i32.add (local.get 0) (i32.const 1))))

  ;; Grows the memory a page at a time until it can't, then touches the
  ;; last page. Returns the number of pages.
  (func (export "hog") (result i32)
    (block $full
      (loop $more
        (br_if $full (i32.eq (memory.grow (i32.const 1)) (i32.const -1)))
        (br $more)))
    (i32.store8
      (i32.sub (i32.mul (memory.size) (i32.const 65536)) (i32.const 1))
      (i32.const 1))
    (memory.size)))
