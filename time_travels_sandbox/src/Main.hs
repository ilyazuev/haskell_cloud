{-# LANGUAGE TemplateHaskell,LambdaCase,RecordWildCards,MultiParamTypeClasses,FlexibleInstances,FlexibleContexts #-}
{-# LANGUAGE RankNTypes,MonadComprehensions,TransformListComp,DeriveDataTypeable,DeriveGeneric #-}
module Main where

import Data.Binary (Binary)
import Data.Typeable (Typeable)
import Data.Maybe
import GHC.Generics (Generic)
import qualified Control.Distributed.Process as P
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node (initRemoteTable,forkProcess)
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Distributed.Process
import System.Environment
import Control.Monad
import Control.Monad.Par
import System.Random
import Control.Concurrent
import Control.Concurrent.STM
import Data.Time.Clock.POSIX
import Data.Global
----------------------------------------- DeriveDataTypeable, DeriveGeneric, TemplateHaskell
randomDelay::IO()
randomDelay=do 
    r<-randomRIO(2,5) 
    threadDelay(r*1000000)

forkDelay::Int->Process()->Process()
forkDelay n f=replicateM_ n$ spawnLocal(liftIO(randomDelay)>>f)

getCurrSec=round`fmap`getPOSIXTime

goToYear::String->Integer->TVar Int->TVar[(Integer,String)]->STM()
goToYear person year freeTmMchns busyYears=do
    ftm<-readTVar freeTmMchns
    byrs<-readTVar busyYears
    if ftm==0 || Nothing/=lookup year byrs || any(\(_,p)->p==person)byrs
        then retry 
        else do
            writeTVar busyYears$ (year,person):byrs
            writeTVar freeTmMchns (ftm-1)
-- main=print$ elem 2 [1,2,3] -- main=print$ drop 2 [1,2,3] main=print$ filter(/=2)[1,2,3] main=print$ lookup 2013 [(2013,"qwe"),(2015,"asdd")] main=print$ any(\(_,p)->"qwe1"==p)[(2013,"qwe"),(2015,"asdd")]

goFromYear::Integer->TVar Int->TVar[(Integer,String)]->STM()
goFromYear year freeTmMchns busyYears=do
    ftm<-readTVar freeTmMchns
    byrs<-readTVar busyYears
    writeTVar freeTmMchns (ftm+1)
    writeTVar busyYears$ filter(\(y,_)->y/=year)byrs

data GetTimeMachine=GetTimeMachine P.ProcessId String Integer deriving(Typeable,Generic)
instance Binary GetTimeMachine

timeTravel::P.ProcessId->String->Integer->TVar Int->TVar[(Integer,String)]->MVar()->Process()
timeTravel master person year freeTmMchns busyYears prntLck=do
    -- let prints s=withMVar prntLck$ \_->putStrLn$ s++" "++person++" "++show year
    let prints s=say$ s++" "++person++" "++show year
    b<-liftIO$ getCurrSec
    fb<-liftIO$ getFb
    say$ "begin "++show b++"; Free machines & busy years: "++show fb++". "
    pid<-P.getSelfPid
    -- say$ "P.send "++show master++" (GetTimeMachine "++show pid++" "++person++" "++show year++")"
    P.send master (GetTimeMachine pid person year)
    "OK"<-expect
    -- -- getTmMchnFromQueue person year tmMchnQueue prntLck
    liftIO$ do
        atomically$ goToYear person year freeTmMchns busyYears
        threadDelay 2000000
        atomically$ goFromYear year freeTmMchns busyYears
    e<-liftIO$ getCurrSec
    fb<-liftIO$ getFb
    say$ "end "++show b++"  "++show (e-b)++"; Free machines & busy years: "++show fb++". "
    return()
    where getFb=atomically$ do 
                    ftm<-readTVar freeTmMchns
                    byrs<-readTVar busyYears
                    return(ftm,byrs)

timeTravels::P.ProcessId->[String]->[Integer]->P.Process()
timeTravels master persons years=do
    (prntLck,freeTmMchns,busyYears)<-liftIO$ do
        p<-newMVar()
        f<-newTVarIO 5
        b<-newTVarIO []
        return(p,f,b)
    mapM_ (\(person,year)->forkDelay 2$ timeTravel master person year freeTmMchns busyYears prntLck)$ [(p,y)|p<-persons,y<-years]
    -- forkIO$ tmMchnService tmMchnQueue prntLck 
    -- -- mapM_ (\(person,year)->print$ person++"->"++show year)$ [(p,y)|p<-persons,y<-years]
    -- _<-getLine
    ftm<-liftIO$ atomically$ readTVar freeTmMchns
    say$ "Free machines: "++show ftm
    return()
-- main=timeTravels["John Doe","Rock Mike","Jane Doe","Jose Rohn","Greg Torch","Hork Din","Lee Bohn"][2013,2014,2001,2017]

data SlaveStart=SlaveStart P.ProcessId deriving(Typeable,Generic)
instance Binary SlaveStart
data SlaveGetTimeTravelsAndYears=SlaveGetTimeTravelsAndYears P.ProcessId deriving(Typeable,Generic)
instance Binary SlaveGetTimeTravelsAndYears
data SlaveRequest=SlaveRequest P.ProcessId String deriving(Typeable,Generic)
instance Binary SlaveRequest
data MasterResponse=MasterResponse String deriving(Typeable,Generic)
instance Binary MasterResponse
slaveStart::P.Process()
slaveStart=do
    SlaveStart master<-P.expect
    pid<-P.getSelfPid
    -- let myNodeId=P.processNodeId pid
    -- P.say$ "Local slave node id="++show myNodeId++". Getting SlaveGetTimeTravelsAndYears"
    -- whereisRemoteAsync myNodeId "timeTravelsAndYears"
    -- jrpid<-receiveWait
    --    [ match (\(WhereIsReply "timeTravelsAndYears" mPid) ->return mPid)
    --    , match (\(NodeMonitorNotification {}) ->return Nothing)
    --    ]
    -- -- jrpid<-whereis "timeTravelsAndYears"
    -- if isNothing jrpid
    --     then say "timeTravelsAndYears not found."
    --     else do
    --         let rpid=fromJust jrpid
    --         say$ "rpid="++show rpid
    --         P.send rpid$ SlaveGetTimeTravelsAndYears pid
    --         (travelers,years)<-expect::Process([String],[Integer])
    --         say$ show travelers++" "++show years
    --         forever$ do 
    --              P.liftIO$ putStrLn "response from master"
    --              P.liftIO$ threadDelay 1000000
    --     -- P.processNodeId
    --     -- spawnLocal
    --              P.send master (SlaveRequest pid "rqst")
    --              MasterResponse rspns<-P.expect
    --              P.say$ "Response: "++rspns
    --         -- timeTravels["John Doe","Rock Mike","Jane Doe","Jose Rohn","Greg Torch","Hork Din","Lee Bohn"][2013,2014,2001,2017]

    ga@(p,y)<-liftIO$ readMVar globalArgMVar
    P.say$ "globalArgMVar = " ++ show ga
    timeTravels master p y -- ["John Doe","Rock Mike","Jane Doe","Jose Rohn","Greg Torch","Hork Din","Lee Bohn"][2013,2014,2001,2017]

globalArgMVar::MVar([String],[Integer])
globalArgMVar=declareEmptyMVar"globalArgMVar"

-- argsHolder::P.Process()
-- argsHolder=do
--     pid<-getSelfPid
--     let myNodeId=P.processNodeId pid
--     P.say$ "Local slave node id="++show myNodeId++". argsHolder"
--     register "timeTravelsAndYears" pid
--     SlaveGetTimeTravelsAndYears rpid<-expect
--     P.send rpid$ ((["John Doe","Rock Mike","Jane Doe","Jose Rohn","Greg Torch","Hork Din","Lee Bohn"],[2013,2014,2001,2017])::([String],[Integer]))
-- remotable['slaveStart,'argsHolder]

remotable['slaveStart]

master::[P.NodeId]->P.Process()
master nodes=do
    P.liftIO.putStrLn$ "Slaves: "++show nodes
    masterPid<-P.getSelfPid
    mapM_(\node->do slavePid<-P.spawn node $(mkStaticClosure 'slaveStart)
                    P.send slavePid (SlaveStart masterPid)) nodes
    P.say$ "Found slaves: "++show nodes
    -- forever$ do GalaxyFound g<-P.expect
    --             P.say$ "Found galaxy: "++g
    -- forever$ do P.receiveWait [
    --                  P.match$ \(SlaveRequest slave request)->do 
    --                                 P.say$ "Request: "++request
    --                                 P.liftIO$ threadDelay 1000000
    --                                 P.send slave (MasterResponse "rspns")
    --                 -- ,match$ \LostInWormHole->P.say$ "Lost in wormhole"
    --                 ]
    tmMchnQueue<-liftIO$ newTBQueueIO 5
    spawnLocal$ tmMchnService tmMchnQueue
    say "Time Machine Service started"
    forever$ do P.receiveWait [
                     P.match$ \(GetTimeMachine rpid person year)->do 
                                    getTmMchnFromQueue person year tmMchnQueue
                                    P.send rpid "OK"
                    ]
    return()

tmMchnService::TBQueue(String,Integer)->Process()
tmMchnService tmMchnQueue=do
    forever$ do (p,y)<-liftIO$ atomically$ do
                            (p,y)<-readTBQueue tmMchnQueue
                            return(p,y)
                P.say$ "got time machine for "++p++" "++show y

getTmMchnFromQueue::String->Integer->TBQueue(String,Integer)->Process()
getTmMchnFromQueue person year tmMchnQueue=do
    say$ "try getting time machine for "++person++" "++show year
    liftIO$ atomically$ writeTBQueue tmMchnQueue (person,year)

-- main=print$ 123
main=mainWithArgs
mainWithArgs=do 
    args<-getArgs
    case args of 
        ["master",host,port]->do
            backend<-initializeBackend host port (Main.__remoteTable initRemoteTable)
            startMaster backend master
        -- ["slave",host,port]->do
        --     putMVar globalArgMVar(["John Doe","Rock Mike","Jane Doe","Jose Rohn","Greg Torch","Hork Din","Lee Bohn"],[2013,2014,2001,2017])
        ["slave",host,port,globalArg]->do
            putStrLn globalArg
            putMVar globalArgMVar (read globalArg::([String],[Integer])) -- (["John Doe","Rock Mike","Jane Doe","Jose Rohn","Greg Torch","Hork Din","Lee Bohn"],[2013,2014,2001,2017])
            putStrLn "slave starting1"
            backend<-initializeBackend host port (Main.__remoteTable initRemoteTable)
            -- putStrLn "slave starting2"
            -- forkIO$ do
            --     threadDelay 3000000
            --     backendTransferArgs<-initializeBackend host port (Main.__remoteTable initRemoteTable)
                -- startMaster backendTransferArgs$ \nodes->do
                --         say$ "Nodes for args "++show nodes
                --         slaves<-findSlaves backendTransferArgs
                --         say$ "Slaves for args "++show slaves
                --         peers<-liftIO$ findPeers backendTransferArgs 1000000 
                --         say$ "Peers for args "++show peers
                --         pid<-P.getSelfPid
                --         forM_ peers$ \node->do P.spawn node $(mkStaticClosure 'argsHolder)
                --         s<-expect::Process String
                --         return()
            -- forkIO$ do
            --     nodes <- liftIO $ findPeers backend 1000000
            --     forM_ nodes $ \nid -> whereisRemoteAsync nid "slaveController"
            -- node<-newLocalNode backend
            -- forkProcess node$ do
            --     liftIO$ threadDelay 5000000
            --     pid<-getSelfPid
            --     liftIO$ putStrLn "registering timeTravelsAndYears"
            --     register "timeTravelsAndYears" pid
            --     jrpid<-whereis "timeTravelsAndYears"
            --     -- liftIO$ if isNothing jrpid then putStrLn "process is not registered" else putStrLn "registered timeTravelsAndYears "
            --     let myNodeId=P.processNodeId pid
            --     P.say$ "Local slave node id="++show myNodeId
            --     P.say$ if isNothing jrpid then "process is not registered" else "registered timeTravelsAndYears "
            --     -- forever$ do
            --     SlaveGetTimeTravelsAndYears rpid<-expect
            --     say "send timeTravelsAndYears"
            --     P.send rpid$ ((["John Doe","Rock Mike","Jane Doe","Jose Rohn","Greg Torch","Hork Din","Lee Bohn"],[2013,2014,2001,2017])::([String],[Integer]))
            putStrLn "slave starting"
            startSlave backend
        _->do putStrLn "Unknown parameters"



