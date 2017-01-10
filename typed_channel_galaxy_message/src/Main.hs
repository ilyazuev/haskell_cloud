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
-- data GalaxyMessage=LookForGalaxy ProcessId|GalaxyFound String deriving(Typeable,Generic)
data GalaxyMessage=LookForGalaxy(SendPort GalaxyMessage)|GalaxyFound String deriving(Typeable,Generic)
instance Binary GalaxyMessage

data WormHoleMessage=LostInWormHole deriving(Typeable,Generic)
instance Binary WormHoleMessage

traveller::Process()
traveller=do LookForGalaxy sendPort<-expect
             sendChan sendPort (GalaxyFound "Andromeda")

remotable['traveller]

master::[NodeId]->Process()
master nodes=
    forM_ nodes$ \node->do 
                     pid<-spawn node $(mkStaticClosure 'traveller)
                     (sendPort,rcvPort)<-newChan
                     send pid (LookForGalaxy sendPort)
                     GalaxyFound g<-receiveChan rcvPort
                     say$ "Found galaxy: "++g

main=do 
    args<-getArgs
    case args of 
        ["master",host,port]->do
            backend<-initializeBackend host port (Main.__remoteTable initRemoteTable)
            putStrLn "master starting"
            startMaster backend master
        ["traveller",host,port]->do
            putStrLn "slave initializing"
            backend<-initializeBackend host port (Main.__remoteTable initRemoteTable)
            putStrLn "slave starting"
            startSlave backend
        _->do putStrLn "Unknown parameters"