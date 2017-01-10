{-# LANGUAGE TemplateHaskell,LambdaCase,RecordWildCards,MultiParamTypeClasses,FlexibleInstances,FlexibleContexts #-}
{-# LANGUAGE RankNTypes,MonadComprehensions,TransformListComp,DeriveDataTypeable,DeriveGeneric #-}
module Main where

import Data.Binary (Binary)
import Data.Typeable (Typeable)
import GHC.Generics (Generic)
import Control.Distributed.Process
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node (initRemoteTable)
import Control.Distributed.Process.Backend.SimpleLocalnet
import System.Environment
import Control.Monad
import System.Random

----------------------------------------- DeriveDataTypeable, DeriveGeneric, TemplateHaskell
-- distributed-process, binary, distributed-process-simplelocalnet
-- data GalaxyMessage=LookForGalaxy|GalaxyFound String
data GalaxyMessage=LookForGalaxy ProcessId|GalaxyFound String deriving(Typeable,Generic)
instance Binary GalaxyMessage

data WormHoleMessage=LostInWormHole deriving(Typeable,Generic)
instance Binary WormHoleMessage


-- traveller::Process()
-- traveller=do LookForGalaxy master<-expect
--              -- поиск галактик в пространстве-времени 
--              send master (GalaxyFound "Andromeda")
traveller::Process()
-- traveller=undefined
traveller=do
    liftIO$ putStrLn "Connected with master node 2"
    LookForGalaxy m<-expect
    b<-liftIO$ randomRIO (True,False) --генерирование случайного boolean
    if b then send m (GalaxyFound "Andromeda") else send m LostInWormHole
remotable['traveller]

main=do 
    args<-getArgs
    case args of 
        ["traveller",host,port]->do
            backend<-initializeBackend host port (Main.__remoteTable initRemoteTable)
            -- backend<-initializeBackend host port initRemoteTable
            putStrLn "slave starting"
            startSlave backend
        _->do putStrLn "Unknown parameters"