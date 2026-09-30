(module
  (func (export "add") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.add)
  (func (export "add_f64") (param f64 f64) (result f64)
    local.get 0
    local.get 1
    f64.add))
