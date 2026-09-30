# modules print their exports and imports

    Code
      print(wasm_module(fixture("start")))
    Output
      <nanowasm_module> 58 bytes
      exports:
        get  function  () -> i32
      imports: none

---

    Code
      print(wasm_module(fixture("imports")))
    Output
      <nanowasm_module> 78 bytes
      exports:
        f  function  () -> ()
      imports:
        env.log  function  (i32) -> ()
        env.mem  memory    min 1
        js.g     global    i32
        js.tbl   table     funcref min 1

