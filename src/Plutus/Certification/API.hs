{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE BlockArguments #-}
module Plutus.Certification.API
  ( API
  , NamedAPI(..)
  , VersionV1(..)
  , RunIDV1(..)
  , FlakeRefV1(..)
  , RunStatusV1(..)
  , StepState(..)
  ) where

import Servant.API
import Servant.API.Generic
import Servant.API.Verbs
import Data.Version
import Data.Aeson
import Data.Aeson.Encoding
import Network.URI
import Data.UUID
import Data.ByteString.Lazy.Char8
import Data.Text hiding (unpack, pack)

type API = NamedRoutes NamedAPI
data NamedAPI mode = NamedAPI
  { version :: mode :- "version" :> Get '[JSON] VersionV1
  , versionHead :: mode :- "version" :> HeadNoContent
  , createRun :: mode :- "run" :> ReqBody '[PlainText] FlakeRefV1 :> PostCreated '[OctetStream, PlainText, JSON] RunIDV1
  , getRun :: mode :- "run" :> Capture "id" RunIDV1 :> Get '[JSON] RunStatusV1
  } deriving stock Generic

newtype VersionV1 = VersionV1 { version :: Version }

versionV1Branch :: VersionV1 -> [Int]
versionV1Branch v = versionBranch $ v.version

instance ToJSON VersionV1 where
  toEncoding = toEncoding . versionV1Branch
  toJSON = toJSON . versionV1Branch

instance FromJSON VersionV1 where
  parseJSON v = VersionV1 . makeVersion <$> parseJSON v

newtype FlakeRefV1 = FlakeRef { uri :: URI }

instance MimeUnrender PlainText FlakeRefV1 where
  mimeUnrender _ uribs = case parseAbsoluteURI uristr of
      Just u -> case u.uriScheme of
        "github:" -> Right $ FlakeRef u
        s -> Left $ "URI '" ++ uristr ++ "' must be a github: flakeref, not '" ++ s ++ "'"
      Nothing -> Left $ "couldn't not parse '" ++ uristr ++ "' as an absolute URI"
    where
      uristr = unpack uribs

instance MimeRender PlainText FlakeRefV1 where
  mimeRender _ ref = pack $ uriToString id ref.uri ""

newtype RunIDV1 = RunID { uuid :: UUID } deriving newtype (FromHttpApiData, ToHttpApiData, ToJSON)

instance MimeRender PlainText RunIDV1 where
  mimeRender _ rid = toLazyASCIIBytes rid.uuid

instance MimeRender OctetStream RunIDV1 where
  mimeRender _ rid = toByteString rid.uuid

instance MimeUnrender OctetStream RunIDV1 where
  mimeUnrender _ ridbs = case fromByteString ridbs of
    Just rid -> pure $ RunID rid
    Nothing -> Left $ "couldn't parse '" ++ (unpack ridbs) ++ "' as a run ID"

data StepState
  = Running
  | Failed deriving stock (Eq, Ord)

instance ToJSON StepState where
  toJSON Running = String "running"
  toJSON Failed = String "failed"

  toEncoding Running = text "running"
  toEncoding Failed = text "failed"

instance FromJSON StepState where
  parseJSON = withText "StepState" go
    where
      go t
        | t == "running" = pure Running
        | t == "failed" = pure Failed
        | otherwise = fail $ "unknown step state " ++ show t

data RunStatusV1
  = Queued
  | Preparing !StepState
  | Building !StepState
  | Certifying !StepState
  | Finished !Value deriving stock (Eq, Ord)

instance ToJSON RunStatusV1 where
  toJSON Queued = object
    [ "status" .= String "queued"
    ]
  toJSON (Preparing s) = object
    [ "status" .= ("preparing" :: Text)
    , "state"  .= s
    ]
  toJSON (Building s) = object
    [ "status" .= ("building" :: Text)
    , "state"  .= s
    ]
  toJSON (Certifying s) = object
    [ "status" .= ("certifying" :: Text)
    , "state"  .= s
    ]
  toJSON (Finished v) = object
    [ "status" .= ("finished" :: Text)
    , "result" .= v
    ]

  toEncoding Queued = pairs
    ( "status" .= ("queued" :: Text)
    )
  toEncoding (Preparing s) = pairs
    ( "status" .= ("preparing" :: Text)
   <> "state"  .= s
    )
  toEncoding (Building s) = pairs
    ( "status" .= ("building" :: Text)
   <> "state"  .= s
    )
  toEncoding (Certifying s) = pairs
    ( "status" .= ("certifying" :: Text)
   <> "state"  .= s
    )
  toEncoding (Finished v) = pairs
    ( "status" .= ("finished" :: Text)
   <> "result" .= v
    )

instance FromJSON RunStatusV1 where
  parseJSON = withObject "RunStatusV1" \o -> do
    status <- o .: "status"
    let go
          | status == ("queued" :: Text) = pure Queued
          | status == "preparing" = Preparing <$> o .: "state"
          | status == "building" = Building <$> o .: "state"
          | status == "certifying" = Certifying <$> o .: "state"
          | status == "finished" = Finished <$> o.: "result"
          | otherwise = fail $ "unknown status " ++ show status
    go
