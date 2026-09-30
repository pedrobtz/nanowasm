;; A start function that traps, so instantiation fails.
(module
  (func $start unreachable)
  (start $start))
