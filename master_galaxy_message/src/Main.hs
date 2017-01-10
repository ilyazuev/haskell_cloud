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
traveller=undefined
-- traveller=do
--     liftIO$ putStrLn "Connected with master node 1"
--     LookForGalaxy m<-expect
--     b<-liftIO$ randomRIO (True,False) --генерирование случайного boolean
--     if b then send m (GalaxyFound "Andromeda 1") else send m LostInWormHole
remotable['traveller]

master::[NodeId]->Process()
master nodes=do
    liftIO.putStrLn$ "Slaves: "++show nodes
    myPid<-getSelfPid
    mapM_(\node->do pid<-spawn node $(mkStaticClosure 'traveller)
                    send pid (LookForGalaxy myPid)) nodes
    say$ "Found slaves: "++show nodes
    -- forever$ do GalaxyFound g<-expect
    --             say$ "Found galaxy: "++g
    forever$ do receiveWait [
                     match$ \(GalaxyFound g)->say$ "Found galaxy: "++g
                    ,match$ \LostInWormHole->say$ "Lost in wormhole"]

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