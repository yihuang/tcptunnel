{-# LANGUAGE ViewPatterns #-}
import System.Environment
import Control.Monad.IO.Class (liftIO)
import Data.Conduit
import Data.Conduit.Network

main = do
    [read -> port] <- getArgs
    runTCPServer
        (ServerSettings port Nothing)
        (\src sink -> do
            liftIO $ putStrLn "open connection"
            src $$ sink
            liftIO $ putStrLn "connection lost"
        )
