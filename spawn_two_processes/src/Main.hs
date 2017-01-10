{-# LANGUAGE TemplateHaskell,LambdaCase,RecordWildCards,MultiParamTypeClasses,FlexibleInstances,FlexibleContexts #-}
{-# LANGUAGE RankNTypes,MonadComprehensions,TransformListComp,DeriveDataTypeable,DeriveGeneric #-}
module Main where

import Control.Concurrent(threadDelay)
import Control.Monad(forever)
import Control.Distributed.Process
import Control.Distributed.Process.Node
import Network.Transport.TCP (createTransport, defaultTCPParameters)
-- import qualified Network.Transport as T

replyBack::(ProcessId,String)->Process()
replyBack(sender,msg)=send sender$ msg++"123"

logMessage::String->Process()
logMessage msg=say$ "handling "++msg

test::IO()
test=do
    Right t<-createTransport "127.0.0.1" "10501" defaultTCPParameters
    node<-newLocalNode t initRemoteTable
    runProcess node$ do
        -- Spawn another worker on the local node
        echoPid<-spawnLocal$ forever$ do
            -- Test our matches in order against each message in the queue
            receiveWait [match logMessage, match replyBack]

            -- The `say` function sends a message to a process registered as "logger".
            -- By default, this process simply loops through its mailbox and sends
            -- any received log message strings it finds to stderr.
        say "Send some messages!"
        send echoPid "Hello"
        self<-getSelfPid
        send echoPid (self, "hello2")

        -- expectTimeout waits for a message or times out after "delay"

        m<-expectTimeout 1000000
        case m of
            -- Die immediately - throws a ProcessExitException with the given reason
            Nothing->die "Nothing come back"
            Just s->say$ "got "++s++" back!"
    _<-getLine
    return()
-- main=print$ 123
main=test
