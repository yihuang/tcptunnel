module Data.Conduit.Concurrent where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Resource

import Control.Concurrent
import qualified Control.Concurrent.Lifted as Lifted

-- | sub thread will auto-terminated when `ResourceT' out of scope.
safeFork :: ResourceT IO () -> ResourceT IO ThreadId
safeFork io = do
    tid <- Lifted.fork io
    _ <- register (Lifted.killThread tid >> liftIO (putStrLn ("kill thread " ++ show tid)))
    return tid
