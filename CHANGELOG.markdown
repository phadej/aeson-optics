1.1 [2019.09.26]
----------------
* Generalize the type of `_JSON` from `Prism' t a` to `Prism t t a b`. If you
  wish to continue to use the less general type, use the newly added `_JSON'`
  prism.
* Add pattern synonyms corresponding to the `Prism`s that `lens-aeson`
  provides.
* Fix the test suite on 32-bit architectures.

1.0.2
-----
* Support `doctest-0.12`

1.0.1
-----
* Revamp `Setup.hs` to use `cabal-doctest`. This makes it build
  with `Cabal-2.0`, and makes the `doctest`s work with `cabal new-build` and
  sandboxes.

1.0.0.5
----
* Fix tests to work against vector-0.11
* Documentation fixes
* No functional changes since 1.0.0.4

1.0.0.3
----
* Move lens upper bound to < 5 like the other packages in the family

1
----
* Module migrated from lens package to Data.Aeson.Lens

0.1.2
-----
* Added `members` and `values`

0.1.1
-----
* Broadened dependencies

0.1
---
* Repository initialized

