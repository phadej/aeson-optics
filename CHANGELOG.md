# 1.2.2

* Drop support for GHCs prior GHC-8.6.5

# 1.2.1

* Drop dependency on `attoparsec`. Use `aeson`s `decode` to parse `Value`.

# 1.2.0.1

* Drop direct dependency on `unordered-containers`

# 1.2

Release corresponding to [`lens-aeson-1.2`](https://hackage.haskell.org/package/lens-aeson-1.2)
API changes.

* Require `aeson-2.0.3.*` and `optics-core-0.4.1` or greater.
* Drop support for GHC-8.0
* Change the types of `_Object`, `key`, and `members`:

  ```diff
  -_Object :: Prism' t (HashMap Text Value)
  +_Object :: Prism' t (KeyMap Value)

  -key :: AsValue t => Text -> AffineTraversal' t Value
  +key :: AsValue t => Key  -> AffineTraversal' t Value

  -members :: AsValue t => IndexedTraversal' Text t Value
  +members :: AsValue t => IndexedTraversal' Key  t Value
  ```

  This mirrors similar changes made in `aeson-2.0.*`, where the type of
  `Object`'s field was changed from `HashMap Text Value` to `KeyMap Value`.

  The `Ixed Value` instance changes similarly:

  ```diff
  -type instance Index Value = Text
  +type instance Index Value = Key
  ```
* Remove `Primitive` and `AsPrimitive`, since https://tools.ietf.org/html/rfc7159
  de-emphasized the notion of primitive versus composite JSON values.
  * The `AsPrimitive` methods (`_Value`, `_String`, and `_Bool`) are now
    `AsValue` methods.
  * `_Number`'s default signature, `Bool_`, `String_`, and `Null_` now have an
    `AsValue` constraint.
* Add an `IsKey` class, whose method `_Key` is an `Iso` for converting values
  to and from a `Key`.

# 1.1.1

- Support `aeson-2.0.0.0`: add instances for `KeyMap`.
