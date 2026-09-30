;; One function per trap kind.
(module
  (type $void (func))
  (memory 1)
  (table 1 funcref)
  (func (export "div_s") (param i32 i32) (result i32)
    local.get 0 local.get 1 i32.div_s)
  (func (export "unreachable") unreachable)
  (func (export "load") (param i32) (result i32) local.get 0 i32.load)
  (func (export "trunc") (param f64) (result i32) local.get 0 i32.trunc_f64_s)
  (func $recurse (export "recurse") (param i32) (result i32)
    local.get 0 i32.const 1 i32.add call $recurse)
  ;; Keeps one value on the operand stack across each recursive call, so it
  ;; runs out of stack cells rather than frames.
  (func $deep_stack (export "deep_stack") (param i32) (result i32)
    local.get 0
    local.get 0 i32.const 1 i32.add call $deep_stack
    i32.add)
  (func (export "call_null") i32.const 0 call_indirect (type $void))
  (func (export "call_undefined") i32.const 5 call_indirect (type $void)))
