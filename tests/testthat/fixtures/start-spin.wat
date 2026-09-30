;; A start function that never returns, so only a timeout ends instantiation.
(module
  (func $start (loop $l (br $l)))
  (start $start))
