{-# LANGUAGE DeriveFunctor    #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleInstances #-}
{- |
Contains representations of the top-level JSON-API document structure.
-}
module Network.JSONApi.Document
  ( Document
  , docData
  , docLinks
  , docMeta
  , docIncluded
  , ErrorDocument (..)
  , errorDoc
  , Included
  , getIncluded
  , oneDoc
  , manyDocs
  , composeDoc
  , include
  , includes
  ) where

import Data.Aeson
       (FromJSON, FromJSON1(..), ToJSON, ToJSON1(..), Value, (.:), (.:?),
        (.=), parseJSON1, toJSON1)
import Control.Lens.TH
import qualified Data.Aeson as AE
import qualified Data.DList as DL
import Data.Functor.Compose
import Data.Functor.Identity
import Data.Hashable
import Data.Hashable.Lifted
import Data.Foldable
import Data.Functor.Classes
import qualified Data.HashMap.Strict as HM
import Data.Maybe (catMaybes, fromMaybe)
import qualified GHC.Generics as G
import qualified Network.JSONApi.Error as E
import Network.JSONApi.Link as L
import Network.JSONApi.Meta as M
import Network.JSONApi.Resource (Resource, ResourcefulEntity)
import qualified Network.JSONApi.Resource as R

{- |
The 'Document' type represents the top-level JSON-API requirement.

@data@ attribute - the resulting JSON may be either a singleton resource
or a list of resources. See 'Resource' for the construction.

For more information see: <http://jsonapi.org/format/#document-top-level>
-}
data Document f a = Document
  { _docData  ::  Compose f R.Resource a
  , _docLinks ::  Links
  , _docMeta  ::  Meta
  , _docIncluded :: [Value]
  } deriving (G.Generic, G.Generic1)

instance (Show1 f, Show a) => Show (Document f a) where
  showsPrec n v =
    showString "Document {data = " .
    showsPrec1 n (_docData v) .
    showString ", links = " .
    showsPrec n (_docLinks v) .
    showString ", meta = " .
    showsPrec n (_docMeta v) .
    showString ", included = " .
    showsPrec n (_docIncluded v) .
    showString "}"

instance (Eq1 f, Eq a) => Eq (Document f a) where
  (==) a b =
    eq1 (_docData a) (_docData b) &&
    _docLinks a == _docLinks b &&
    _docMeta a == _docMeta b &&
    _docIncluded a == _docIncluded b

instance (Functor f, Hashable1 f) => Hashable1 (Document f)
instance (Hashable1 f, Hashable a) => Hashable (Document f a) where
  hashWithSalt s x =
    s `hashWithSalt1`
    _docData x `hashWithSalt`
    _docLinks x `hashWithSalt`
    _docMeta x `hashWithSalt` _docIncluded x

makeLenses ''Document

instance (ToJSON1 f, ToJSON a) => ToJSON (Document f a) where
  toJSON (Document vs links meta included) = AE.object
    (("data" .= toJSON1 vs) : optionals)
    where
      optionals = catMaybes
        [ if (HM.null $ fromLinks links) then Nothing else Just ("links" .= links)
        , if (HM.null $ fromMeta meta) then Nothing else Just ("meta"  .= meta)
        , if (null included) then Nothing else Just ("included" .= included)
        ]

instance (FromJSON1 f, FromJSON a) => FromJSON (Document f a) where
  parseJSON = AE.withObject "document" $ \v -> do
    dat <- v .:  "data"
    d <- parseJSON1 dat
    l <- v .:? "links"
    m <- v .:? "meta"
    i <- v .:? "included"
    return $ Document
      d
      (fromMaybe mempty l)
      (fromMaybe mempty m)
      (fromMaybe [] i)

{- |
The 'Included' type is an abstraction used to constrain the @included@
section of the Document to JSON serializable Resource objects while
enabling a heterogeneous list of Resource types.

No data constructors for this type are exported as we need to
constrain the 'Value' to a heterogeneous list of Resource types.
See 'mkIncludedResource' for creating 'Included' types.
-}
newtype Included = Included (DL.DList Value)
  deriving (Show, Semigroup, Monoid)

getIncluded :: Included -> [Value]
getIncluded (Included d) = DL.toList d

{- |
Constructor function for the Document data type.
-}
oneDoc :: (ToJSON (R.ResourceValue a), ResourcefulEntity a) => a -> Document Identity (R.ResourceValue a)
oneDoc = composeDoc . pure . R.toResource

{- |
Constructor function for the Document data type.
-}
manyDocs :: (ToJSON a, ResourcefulEntity a) => [a] -> Document [] (R.ResourceValue a)
manyDocs = composeDoc . fmap R.toResource

{- |
Constructor function for the Document data type. It is possible to create an
invalid Document if the provided @f@ doesn't serialize to either single
@ResourceValue@ or an array of @ResourceValue@s
-}
composeDoc :: f (Resource a) -> Document f a
composeDoc functor = Document (Compose functor) mempty mempty mempty

{- |
Supports building compound documents
<http://jsonapi.org/format/#document-compound-documents>
-}
include :: (AE.ToJSON (R.ResourceValue a), ResourcefulEntity a) => a -> Included
include = Included . DL.singleton . AE.toJSON . R.toResource

{- |
Supports building compound documents
<http://jsonapi.org/format/#document-compound-documents>
-}
includes :: (Foldable f, AE.ToJSON (R.ResourceValue a), ResourcefulEntity a) => f a -> Included
includes = Included . DL.fromList . fmap (AE.toJSON . R.toResource) . toList

{- |
The 'ErrorDocument' type represents the alternative form of the top-level
JSON-API requirement.

@error@ attribute - a descriptive object encapsulating application-specific
error detail.

For more information see: <http://jsonapi.org/format/#errors>
-}
data ErrorDocument a = ErrorDocument
  { _errors :: [E.Error a]
  , _errorLinks :: Links
  , _errorMeta :: Meta
  } deriving (Show, Eq, G.Generic)

instance ToJSON (ErrorDocument a) where
  toJSON (ErrorDocument err links meta) = AE.object $ catMaybes
    [ Just ("errors" .= err)
    , if (null $ fromLinks links) then Nothing else Just ("links" .= links)
    , if (HM.null $ fromMeta meta) then Nothing else Just ("meta"  .= meta)
    ]

instance FromJSON (ErrorDocument a) where
  parseJSON = AE.withObject "errors" $ \v -> do
    e <- v .: "errors"
    l <- v .:? "links"
    m <- v .:? "meta"
    return $ ErrorDocument e (fromMaybe mempty l) (fromMaybe mempty m)

errorDoc :: [E.Error a] -> ErrorDocument a
errorDoc es = ErrorDocument es mempty mempty
