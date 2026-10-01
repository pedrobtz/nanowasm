;; A WASI "reactor": no _start, an _initialize the host calls once, and
;; exports that call WASI functions directly.
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "random_get"
    (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 100) "reactor says hi\n")
  (global $ready (export "ready") (mut i32) (i32.const 0))

  (func (export "_initialize") (global.set $ready (i32.const 1)))

  ;; Write the message to fd; returns the WASI errno.
  (func (export "say") (param $fd i32) (result i32)
    (i32.store (i32.const 0) (i32.const 100))
    (i32.store (i32.const 4) (i32.const 16))
    (call $fd_write (local.get $fd) (i32.const 0) (i32.const 1) (i32.const 8)))

  ;; fd_write with its iovec array outside memory: EFAULT.
  (func (export "bad_write") (result i32)
    (call $fd_write (i32.const 1) (i32.const 70000) (i32.const 1) (i32.const 8)))

  ;; len random bytes at offset 200; returns the errno.
  (func (export "random") (param $len i32) (result i32)
    (call $random_get (i32.const 200) (local.get $len))))
