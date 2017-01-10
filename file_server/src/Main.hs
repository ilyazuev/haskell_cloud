{-# LANGUAGE DeriveDataTypeable,DeriveGeneric,TemplateHaskell #-}

import Network.Transport hiding (send) -- (EndPointAddress)
import Network.Transport.TCP
import Control.Distributed.Process
import Control.Distributed.Process.Node as N
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Backend.SimpleLocalnet as SLN

import Control.Concurrent
import Data.List
-- import qualified Data.ByteString as BS
-- import qualified Data.ByteString.Char8 as BS.Char
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map as Map
import Data.Typeable
import GHC.Generics
import Data.Binary
import System.IO
import System.Environment
import System.FilePath
import Text.Read(readMaybe)

data FileServerMsg=OpenFile  ProcessId FilePath
                  |CloseFile ProcessId FilePath
                  |ReadFile  ProcessId FilePath Int Int
                  |WriteFile ProcessId FilePath Int BSC.ByteString deriving(Typeable,Generic)
instance Binary FileServerMsg

data FileClientMsg=OpenGranted  FilePath
                  |OpenDenied   FilePath
                  |CloseConfirm FilePath
                  |ReadResult   FilePath BSC.ByteString
                  |WriteConfirm FilePath deriving(Typeable,Generic)
instance Binary FileClientMsg

fileServer::FilePath->Process()
fileServer root=go Map.empty
    where go::Map.Map FilePath Handle->Process()
          go openFiles=do
            cmd<-expect
            case cmd of
                OpenFile client file
                    |file`Map.member`openFiles->send client (OpenDenied file)
                    |otherwise->do
                        -- hnd<-liftIO$ openBinaryFile (root</>file) ReadWriteMode
                        hnd<-liftIO$ openBinaryFile file ReadWriteMode
                        send client (OpenGranted file)
                        go (Map.insert file hnd openFiles)
                CloseFile client file
                    |Just hnd<-Map.lookup file openFiles->do
                        liftIO$ hClose hnd
                        send client (CloseConfirm file)
                        go (Map.delete file openFiles)
                ReadFile client file offset len
                    |Just hnd<-Map.lookup file openFiles->do
                        fdata<-liftIO$ do hSeek hnd AbsoluteSeek (fromIntegral offset)
                                          BSC.hGet hnd len
                        send client (ReadResult file fdata)
                        go openFiles
                WriteFile client file offset fdata
                    |Just hnd<-Map.lookup file openFiles->do
                        liftIO$ do hSeek hnd AbsoluteSeek (fromIntegral offset)
                                   BSC.hPut hnd fdata
                        send client (WriteConfirm file)
                        go openFiles

serverOpenFile::ProcessId->FilePath->Process()
serverOpenFile server file=do
  us<-getSelfPid
  send server (OpenFile us file)
  OpenGranted _<-expect
  return()

serverCloseFile::ProcessId->FilePath->Process()
serverCloseFile server file=do
  us<-getSelfPid
  send server (CloseFile us file)
  CloseConfirm _<-expect
  return()

serverReadFile::ProcessId->FilePath->Int->Int->Process BSC.ByteString
serverReadFile server file offset len=do
  us<-getSelfPid
  send server (ReadFile us file offset len)
  ReadResult _ fdata<-expect
  return fdata

serverWriteFile::ProcessId->FilePath->Int->BSC.ByteString->Process()
serverWriteFile server file offset fdata=do
  us<-getSelfPid
  send server (WriteFile us file offset fdata)
  WriteConfirm _<-expect
  return()

interactiveLoop::ProcessId->Process()
interactiveLoop server=do
  liftIO$ do putStr "\nenter command> " 
             hFlush stdout
  ln<-liftIO$ getLine
  case words ln of
    ["open",file]->do
        serverOpenFile server file
        interactiveLoop server
    ["close",file]->do
        serverCloseFile server file
        interactiveLoop server
    ["read",file,offstr,lenstr]
        |Just offset<-readMaybe offstr
        ,Just len<-readMaybe lenstr->do
            fdata<-serverReadFile server file offset len
            liftIO$ BSC.putStrLn fdata
            interactiveLoop server
    ["write",file,offstr,fdata]
        |Just offset<-readMaybe offstr->do
            fdata<-serverWriteFile server file offset (BSC.pack fdata)
            interactiveLoop server
    ["exit"]->return()
    _->do liftIO$ putStrLn "unrecognized command"
          interactiveLoop server

runServer::LocalNode->IO()
runServer node=
    runProcess node$ do
        server<-getSelfPid
        register "file-server" server
        fileServer "."

runClient::LocalNode->[NodeId]->IO()
runClient node peers=
    runProcess node$ do
        server<-findServer peers
        interactiveLoop server
    where 
        findServer[]=do
            liftIO$ do putStrLn$ "cannot find file server"
                       hFlush stdout
            die "cannot find file server"
        findServer(p:ps)=do
            whereisRemoteAsync p "file-server"
            WhereIsReply _ mpid<-expect
            case mpid of
                Just serverPid->return serverPid
                _->findServer ps
-- main=do
--     [mode,port]<-getArgs
--     backend<-initializeBackend "127.0.0.1" port initRemoteTable
--     node<-SLN.newLocalNode backend
--     case mode of
--         "server"->runServer node
--         "client"->do peers<-findPeers backend 1000000
--                      putStrLn$ show peers
--                      hFlush stdout
--                      runClient node peers
main=do
    args<-getArgs
    case args of
        [port]->do
            makeNode port>>=runServer
        [port,serverAddress]->do
            let addr=EndPointAddress(BSC.pack serverAddress)
            node<-makeNode port
            runClient node [NodeId addr]
    where makeNode port=do
            Right transport<-createTransport "127.0.0.1" port defaultTCPParameters
            N.newLocalNode transport initRemoteTable

