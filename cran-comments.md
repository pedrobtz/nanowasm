## Submission

This is the first submission of nanowasm.

## Bundled code

src/toywasm/ contains part of toywasm (https://github.com/yamt/toywasm), a
WebAssembly interpreter by YAMAMOTO Takashi, under the 2-clause BSD licence
(inst/TOYWASM_LICENSE). Its author is listed with the "cph" role, and
inst/COPYRIGHTS records the upstream version and every local change. The
changes adapt it to R's build and to CRAN's checks: no output to
stdout/stderr, no abort(), no GNU C extensions that warn under -pedantic,
and fixes for undefined behaviour reported by UBSan.

## Method references

There are no published references describing the methods in this package.
It embeds an implementation of the WebAssembly specification
(https://webassembly.github.io/spec/).

## R CMD check results

0 errors | 0 warnings | 0 notes
