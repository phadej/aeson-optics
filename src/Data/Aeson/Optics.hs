{-# LANGUAGE CPP                   #-}
{-# LANGUAGE DefaultSignatures     #-}
{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternSynonyms       #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE Trustworthy           #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE ViewPatterns          #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
--------------------------------------------------------------------
-- |
-- Copyright :  (c) Oleg Grenrus 2019, (c) Edward Kmett 2013-2019, (c) Paul Wilson 2012
-- License   :  MIT
-- Maintainer:  Edward Kmett <ekmett@gmail.com>
-- Stability :  experimental
-- Portability: non-portable
--
-- This module also exports orphan @'Ixed' 'Value'@ and
-- @'Plated' 'Value'@ instances.
--------------------------------------------------------------------
module Data.Aeson.Optics
  (
  -- * Numbers
    AsNumber(..)
  , _Integral
  , nonNull
  -- * Objects and Arrays
  , AsValue(..)
  , key, members
  , nth, values
  , IsKey (..)
  -- * Decoding
  , AsJSON(..)
  , _JSON'
  -- * Pattern Synonyms
  , pattern JSON
  , pattern Value_
  , pattern Number_
  , pattern Double
  , pattern Integer
  , pattern Integral
  , pattern Bool_
  , pattern String_
  , pattern Null_
  , pattern Key_
  ) where

import Prelude hiding (null)

import Data.Aeson
       (FromJSON, Result (..), ToJSON, Value (..), encode, fromJSON, toJSON, decode)
import Data.Scientific                 (Scientific)
import Data.Text                       (Text)
import Data.Text.Optics                (packed)
import Data.Text.Short                 (ShortText)
import Data.Vector                     (Vector)

import Optics.At ()
import Optics.Core
import Optics.Indexed ()

import qualified Data.Aeson.Key             as Key
import qualified Data.Aeson.KeyMap          as KM
import qualified Data.ByteString            as Strict
import qualified Data.ByteString.Lazy       as LBS
import qualified Data.Scientific            as Scientific
import qualified Data.Text                  as StrictText
import qualified Data.Text.Encoding         as StrictText
import qualified Data.Text.Lazy             as LazyText
import qualified Data.Text.Lazy.Encoding    as LazyText

-- $setup
-- >>> import Optics.Core
-- >>> import Data.Aeson (Value (..))
-- >>> import Data.Text (Text)
-- >>> import qualified Data.ByteString             as Strict
-- >>> import qualified Data.ByteString.Char8       as Strict.Char8
-- >>> import qualified Data.ByteString.Lazy        as Lazy
-- >>> import qualified Data.ByteString.Lazy.Char8  as Lazy.Char8
-- >>> import qualified Data.Aeson.KeyMap           as KeyMap
-- >>> import qualified Data.Vector                 as Vector
-- >>> :set -XOverloadedStrings
-- >>> import Optics.Operators

------------------------------------------------------------------------------
-- Scientific prisms
------------------------------------------------------------------------------

class AsNumber t where
  -- |
  -- >>> "[1, \"x\"]" ^? nth 0 % _Number
  -- Just 1.0
  --
  -- >>> "[1, \"x\"]" ^? nth 1 % _Number
  -- Nothing
  _Number :: Prism' t Scientific
  default _Number :: AsValue t => Prism' t Scientific
  _Number = _Value%_Number
  {-# INLINE _Number #-}

  -- |
  -- Prism into an 'Double' over a 'Value', 'Primitive' or 'Scientific'
  --
  -- >>> "[10.2]" ^? nth 0 % _Double
  -- Just 10.2
  _Double :: Prism' t Double
  _Double = _Number%iso Scientific.toRealFloat realToFrac
  {-# INLINE _Double #-}

  -- |
  -- Prism into an 'Integer' over a 'Value', 'Primitive' or 'Scientific'
  --
  -- >>> "[10]" ^? nth 0 % _Integer
  -- Just 10
  --
  -- >>> "[10.5]" ^? nth 0 % _Integer
  -- Just 10
  --
  -- >>> "42" ^? _Integer
  -- Just 42
  _Integer :: Prism' t Integer
  _Integer = _Number%iso floor fromIntegral
  {-# INLINE _Integer #-}

instance AsNumber Value where
  _Number = prism Number $ \v -> case v of Number n -> Right n; _ -> Left v
  {-# INLINE _Number #-}

instance AsNumber Scientific where
  _Number = castOptic simple
  {-# INLINE _Number #-}

instance AsNumber Strict.ByteString
instance AsNumber LBS.ByteString
instance AsNumber Text
instance AsNumber LazyText.Text
instance AsNumber String

------------------------------------------------------------------------------
-- Conversion Prisms
------------------------------------------------------------------------------

-- | Access Integer 'Value's as Integrals.
--
-- >>> "[10]" ^? nth 0 % _Integral
-- Just 10
--
-- >>> "[10.5]" ^? nth 0 % _Integral
-- Just 10
_Integral :: (AsNumber t, Integral a) => Prism' t a
_Integral = _Number % iso floor fromIntegral
{-# INLINE _Integral #-}

-- | Prism into non-'Null' values
--
-- >>> "{\"a\": \"xyz\", \"b\": null}" ^? key "a" % nonNull
-- Just (String "xyz")
--
-- >>> "{\"a\": {}, \"b\": null}" ^? key "a" % nonNull
-- Just (Object (fromList []))
--
-- >>> "{\"a\": \"xyz\", \"b\": null}" ^? key "b" % nonNull
-- Nothing
nonNull :: Prism' Value Value
nonNull = prism id (\v -> if isn't _Null v then Right v else Left v)
{-# INLINE nonNull #-}

------------------------------------------------------------------------------
-- Non-primitive traversals
------------------------------------------------------------------------------

class AsNumber t => AsValue t where
  -- |
  -- >>> preview _Value "[1,2,3]" == Just (Array (Vector.fromList [Number 1.0,Number 2.0,Number 3.0]))
  -- True
  _Value :: Prism' t Value

  -- |
  -- >>> "{\"a\": {}, \"b\": null}" ^? key "a" % _Object
  -- Just (fromList [])
  --
  -- >>> "{\"a\": {}, \"b\": null}" ^? key "b" % _Object
  -- Nothing
  --
  -- >>> _Object # KeyMap.fromList [("key", _String # "value")] :: String
  -- "{\"key\":\"value\"}"
  _Object :: Prism' t (KM.KeyMap Value)
  _Object = _Value%prism Object  (\v -> case v of Object o -> Right o; _ -> Left v)

  -- |
  -- >>> preview _Array "[1,2,3]" == Just (Vector.fromList [Number 1.0,Number 2.0,Number 3.0])
  -- True
  _Array :: Prism' t (Vector Value)
  _Array = _Value%prism Array (\v -> case v of Array a -> Right a; _ -> Left v)
  {-# INLINE _Array #-}

  -- |
  -- >>> "{\"a\": \"xyz\", \"b\": true}" ^? key "a" % _String
  -- Just "xyz"
  --
  -- >>> "{\"a\": \"xyz\", \"b\": true}" ^? key "b" % _String
  -- Nothing
  --
  -- >>> _Object # KeyMap.fromList [("key", _String # "value")] :: String
  -- "{\"key\":\"value\"}"
  _String :: Prism' t Text
  _String = _Value%prism String (\v -> case v of String s -> Right s; _ -> Left v)
  {-# INLINE _String #-}

  -- |
  -- >>> "{\"a\": \"xyz\", \"b\": true}" ^? key "b" % _Bool
  -- Just True
  --
  -- >>> "{\"a\": \"xyz\", \"b\": true}" ^? key "a" % _Bool
  -- Nothing
  --
  -- >>> _Bool # True :: String
  -- "true"
  --
  -- >>> _Bool # False :: String
  -- "false"
  _Bool :: Prism' t Bool
  _Bool = _Value%prism Bool (\v -> case v of Bool b -> Right b; _ -> Left v)
  {-# INLINE _Bool #-}

  -- |
  -- >>> "{\"a\": \"xyz\", \"b\": null}" ^? key "b" % _Null
  -- Just ()
  --
  -- >>> "{\"a\": \"xyz\", \"b\": null}" ^? key "a" % _Null
  -- Nothing
  --
  -- >>> _Null # () :: String
  -- "null"
  _Null :: Prism' t ()
  _Null = _Value % prism (const Null) (\v -> case v of Null -> Right (); _ -> Left v)
  {-# INLINE _Null #-}


instance AsValue Value where
  _Value = castOptic simple
  {-# INLINE _Value #-}

instance AsValue Strict.ByteString where
  _Value = _JSON
  {-# INLINE _Value #-}

instance AsValue LBS.ByteString where
  _Value = _JSON
  {-# INLINE _Value #-}

instance AsValue String where
  _Value = strictUtf8%_JSON
  {-# INLINE _Value #-}

instance AsValue Text where
  _Value = strictTextUtf8%_JSON
  {-# INLINE _Value #-}

instance AsValue LazyText.Text where
  _Value = lazyTextUtf8%_JSON
  {-# INLINE _Value #-}

-- |
-- Like 'ix', but for 'Object' with Text indices. This often has better
-- inference than 'ix' when used with OverloadedStrings.
--
-- >>> "{\"a\": 100, \"b\": 200}" ^? key "a"
-- Just (Number 100.0)
--
-- >>> "[1,2,3]" ^? key "a"
-- Nothing
key :: AsValue t => Key.Key -> AffineTraversal' t Value
key i = _Object % ix i
{-# INLINE key #-}

-- | An indexed Traversal into Object properties
--
-- >>> Data.List.sort (itoListOf (members % _Number) "{\"a\": 4, \"b\": 7}")
-- [("a",4.0),("b",7.0)]
--
-- >>> "{\"a\": 4}" & members % _Number %~ (*10)
-- "{\"a\":40}"
members :: AsValue t => IxTraversal' Key.Key t Value
members = _Object % itraversed
{-# INLINE members #-}

-- | Like 'ix', but for Arrays with Int indexes
--
-- >>> "[1,2,3]" ^? nth 1
-- Just (Number 2.0)
--
-- >>> "{\"a\": 100, \"b\": 200}" ^? nth 1
-- Nothing
--
-- >>> "[1,2,3]" & nth 1 .~ Number 20
-- "[1,20,3]"
nth :: AsValue t => Int -> AffineTraversal' t Value
nth i = _Array % ix i
{-# INLINE nth #-}

-- | An indexed Traversal into Array elements
--
-- >>> "[1,2,3]" ^.. values
-- [Number 1.0,Number 2.0,Number 3.0]
--
-- >>> "[1,2,3]" & values % _Number %~ (*10)
-- "[10,20,30]"
values :: AsValue t => IxTraversal' Int t Value
values = _Array % itraversed
{-# INLINE values #-}

strictUtf8 :: Iso' String Strict.ByteString
strictUtf8 = packed % strictTextUtf8

strictTextUtf8 :: Iso' StrictText.Text Strict.ByteString
strictTextUtf8 = iso StrictText.encodeUtf8 StrictText.decodeUtf8

lazyTextUtf8 :: Iso' LazyText.Text LBS.ByteString
lazyTextUtf8 = iso LazyText.encodeUtf8 LazyText.decodeUtf8

_JSON' :: (AsJSON t, FromJSON a, ToJSON a) => Prism' t a
_JSON' = _JSON

class IsKey t where
  -- | '_Key' is an 'Iso' from something to a 'Key'. This is primarily intended
  -- for situations where one wishes to use object keys that are not string
  -- literals and therefore must be converted:
  --
  -- >>> let k = "a" :: Text
  -- >>> "{\"a\": 100, \"b\": 200}" ^? key (k ^. _Key)
  -- Just (Number 100.0)
  --
  -- Note that applying '_Key' directly to a string literal
  -- (e.g., @\"a\" ^. '_Key'@) will likely not typecheck when
  -- @OverloadedStrings@ is enabled.
  _Key :: Iso' t Key.Key

instance IsKey Key.Key where
  _Key = simple
  {-# INLINE _Key #-}

instance IsKey String where
  _Key = iso Key.fromString Key.toString
  {-# INLINE _Key #-}

instance IsKey Text where
  _Key = iso Key.fromText Key.toText
  {-# INLINE _Key #-}

instance IsKey LazyText.Text where
  _Key = iso LazyText.toStrict LazyText.fromStrict % _Key
  {-# INLINE _Key #-}

instance IsKey ShortText where
  _Key = iso Key.fromShortText Key.toShortText
  {-# INLINE _Key #-}

{-
https://github.com/lens/lens-aeson/issues/48
instance IsKey Strict.ByteString where
  _Key = from strictTextUtf8._Key
  {-# INLINE _Key #-}

instance IsKey LBS.ByteString where
  _Key = from lazyTextUtf8._Key
  {-# INLINE _Key #-}
-}

class AsJSON t where
  -- | '_JSON' is a 'Prism' from something containing JSON to something encoded in that structure
  _JSON :: (FromJSON a, ToJSON b) => Prism t t a b

instance AsJSON Strict.ByteString where
  _JSON = iso LBS.fromStrict LBS.toStrict % _JSON
  {-# INLINE _JSON #-}

instance AsJSON LBS.ByteString where
  _JSON = prism' encode decode
  {-# INLINE _JSON #-}

instance AsJSON String where
  _JSON = strictUtf8 % _JSON
  {-# INLINE _JSON #-}

instance AsJSON Text where
  _JSON = strictTextUtf8 % _JSON
  {-# INLINE _JSON #-}

instance AsJSON LazyText.Text where
  _JSON = lazyTextUtf8 % _JSON
  {-# INLINE _JSON #-}

instance AsJSON Value where
  _JSON = prism toJSON $ \x -> case fromJSON x of
    Success y -> Right y;
    _         -> Left x
  {-# INLINE _JSON #-}

------------------------------------------------------------------------------
-- Some additional tests for prismhood; see https://github.com/ekmett/lens/issues/439.
------------------------------------------------------------------------------

-- $LazyByteStringTests
-- >>> "42" ^? (_JSON :: Prism' Lazy.ByteString Value)
-- Just (Number 42.0)
--
-- >>> preview (_Integer :: Prism' Lazy.ByteString Integer) "42"
-- Just 42
--
-- >>> Lazy.Char8.unpack (review (_Integer :: Prism' Lazy.ByteString Integer) 42)
-- "42"

-- $StrictByteStringTests
-- >>> "42" ^? (_JSON :: Prism' Strict.ByteString Value)
-- Just (Number 42.0)
--
-- >>> preview (_Integer :: Prism' Strict.ByteString Integer) "42"
-- Just 42
--
-- >>> Strict.Char8.unpack (review (_Integer :: Prism' Strict.ByteString Integer) 42)
-- "42"

-- $StringTests
-- >>> "42" ^? (_JSON :: Prism' String Value)
-- Just (Number 42.0)
--
-- >>> preview (_Integer :: Prism' String Integer) "42"
-- Just 42
--
-- >>> review (_Integer :: Prism' String Integer) 42
-- "42"

------------------------------------------------------------------------------
-- Orphan instances for lens library interop
------------------------------------------------------------------------------

type instance Index Value = Key.Key

type instance IxValue Value = Value
instance Ixed Value where
  ix i = _Object % ix i
  {-# INLINE ix #-}

{-
instance Plated Value where
  plate f (Object o) = Object <$> traverse f o
  plate f (Array a) = Array <$> traverse f a
  plate _ xs = pure xs
  {-# INLINE plate #-}
-}

type instance Index (KM.KeyMap v) = Key.Key
type instance IxValue (KM.KeyMap v) = v

instance Ixed (KM.KeyMap v)

instance At (KM.KeyMap v) where
  at i = lensVL (\f -> KM.alterF f i)
  {-# INLINE at #-}

instance Each Key.Key (KM.KeyMap a) (KM.KeyMap b) a b where
  each = itraversalVL KM.traverseWithKey
  {-# INLINE[1] each #-}

------------------------------------------------------------------------------
-- Pattern Synonyms
------------------------------------------------------------------------------

pattern JSON :: (FromJSON a, ToJSON a, AsJSON t) => () => a -> t
pattern JSON a <- (preview _JSON -> Just a) where
  JSON a = _JSON # a

pattern Value_ :: (FromJSON a, ToJSON a) => () => a -> Value
pattern Value_ a <- (fromJSON -> Success a) where
  Value_ a = toJSON a

pattern Number_ :: AsNumber t => Scientific -> t
pattern Number_ n <- (preview _Number -> Just n) where
  Number_ n = _Number # n

pattern Double :: AsNumber t => Double -> t
pattern Double d <- (preview _Double -> Just d) where
  Double d = _Double # d

pattern Integer :: AsNumber t => Integer -> t
pattern Integer i <- (preview _Integer -> Just i) where
  Integer i = _Integer # i

pattern Integral :: (AsNumber t, Integral a) => a -> t
pattern Integral d <- (preview _Integral -> Just d) where
  Integral d = _Integral # d

pattern Bool_ :: AsValue t => Bool -> t
pattern Bool_ b <- (preview _Bool -> Just b) where
  Bool_ b = _Bool # b

pattern String_ :: AsValue t => Text -> t
pattern String_ p <- (preview _String -> Just p) where
  String_ p = _String # p

pattern Null_ :: AsValue t => t
pattern Null_ <- (preview _Null -> Just ()) where
  Null_ = _Null # ()

pattern Key_ :: IsKey t => Key.Key -> t
pattern Key_ k <- (preview _Key -> Just k) where
  Key_ k = _Key # k
