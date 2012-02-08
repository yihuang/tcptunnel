module Data.Conduit.TChan where

import Control.Monad.IO.Class (liftIO)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TChan (TChan, readTChan, writeTChan)
import Data.Conduit

sourceTChan :: TChan a -> Source IO a
sourceTChan ch = src
  where
    src = Source pull close
    pull = do
        a <- liftIO $ atomically (readTChan ch)
        return $ Open src a
    close = return ()

sinkTChan :: TChan a -> Sink a IO ()
sinkTChan ch = sink
  where
    sink = SinkData push close
    push input = do
        liftIO $ atomically (writeTChan ch input)
        return $ Processing push close
    close = return ()
