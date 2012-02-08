{-# LANGUAGE BangPatterns, ViewPatterns #-}
import System.Environment (getArgs)
import System.IO.Unsafe (unsafePerformIO)

import Data.Word (Word32)
import Data.Bits (xor)
import Data.Serialize.Get (runGet, getWord32be)
import Data.Monoid (mconcat)
import qualified Blaze.ByteString.Builder as B
import Data.ByteString (ByteString)
import qualified Data.ByteString as S
import qualified Data.IntMap as M
import Data.Attoparsec as A
import Data.IORef (IORef, newIORef, readIORef, atomicModifyIORef)

import Data.Conduit (Sink(SinkData), Conduit, ResourceThrow, SinkResult(Processing), ($$), ($=) )
import qualified Data.Conduit as C
import qualified Data.Conduit.List as C
import qualified Data.Conduit.Attoparsec as C
import Data.Conduit.Network

import Control.Applicative
import Control.Monad.IO.Class (liftIO)
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar
import qualified Control.Concurrent.MVar.Lifted as Lifted
import Control.Concurrent.STM (atomically, newTVarIO, TVar, readTVar, writeTVar)
import Control.Concurrent.STM.TChan (TChan, newTChanIO, writeTChan)

import Data.Conduit.TChan (sourceTChan, sinkTChan)
import Data.Conduit.Concurrent (safeFork)

proxyHost, proxyHost' :: String
proxyPort, proxyPort' :: Int
proxyHost = "127.0.0.1"
proxyPort = 1082
-- for testing on single machine
proxyHost' = "127.0.0.1"
proxyPort' = 1081

------------------------------------------------
-- | Maintain a auto increment unique identity.

type Identity = M.Key

-- | a thread-safe global variable.
identitySource :: TVar Identity
identitySource = unsafePerformIO (newTVarIO 0)

newIdentity :: IO Identity
newIdentity = atomically $ do
    v <- readTVar identitySource
    let !v' = v + 1
    writeTVar identitySource v'
    return v'

------------------------------------------------
-- | encrypt / decrypt message.

encrypt :: ByteString -> ByteString
encrypt = S.map (\w -> w `xor` 0x64)

decrypt :: ByteString -> ByteString
decrypt = encrypt

-----------------------------------------------
-- | Parse and encode tagged frame.

type Tagged = (Identity, Word32, ByteString)

taggedParser :: Parser Tagged
taggedParser = do
    (ident, len) <- A.take 8 >>= either fail return . runGet getWord32N2
    buffer <- A.take (fromIntegral len)
    return (fromIntegral ident, len, decrypt buffer)
  where
    getWord32N2 = (,) <$> getWord32be <*> getWord32be

encodeTagged :: Tagged -> ByteString
encodeTagged (ident, len, buffer) =
    B.toByteString $ mconcat
        [ B.fromWord32be $ fromIntegral ident
        , B.fromWord32be len
        , B.copyByteString $ encrypt buffer
        ]

tagFrame :: Monad m => Identity -> Conduit ByteString m ByteString
tagFrame ident = C.map $ \s -> encodeTagged (ident, fromIntegral (S.length s), s)

untagFrame :: ResourceThrow m => Conduit ByteString m Tagged
untagFrame = C.sequence (C.sinkParser taggedParser)

-- | Map of tunnel identity to data receiving channel of corresponding tunnel.
type TunnelMap = M.IntMap (TChan ByteString)

-- | Receive tagged frame from channel, send them to remote server.
--   [extra thread] Receive tagged frame from remove server, untagg them, and pass then to the corresponding channel.
localClient :: TChan ByteString -> IORef TunnelMap -> Application
localClient ch tunnels src sink = do
    -- start server
    _ <- liftIO $ forkIO $
            runTCPServer
                (ServerSettings proxyPort (Just proxyHost))
                (localServer ch tunnels)
    -- up stream
    _ <- safeFork $ sourceTChan ch $$ sink
    -- down stream
    src $= untagFrame $$ sinkTunnel
  where
    sinkTunnel = SinkData push close
    push (ident, _, buffer) = liftIO $ do
        m <- readIORef tunnels
        case M.lookup ident m of
            Nothing -> putStrLn ("unknown tunnel identity "++show ident)
            Just ch' -> atomically $ writeTChan ch' buffer
        return $ Processing push close
    close = return ()

-- | Receive raw frame from client, tag it, and pass to channel.
--   [extra thread] Receive raw frame from channel, send them back to client.
localServer :: TChan ByteString -> IORef TunnelMap -> Application
localServer ch tunnels src sink = do
    ch' <- liftIO newTChanIO
    ident <- liftIO newIdentity
    liftIO $ atomicModifyIORef tunnels (\m -> (M.insert ident ch' m, ()))
    -- down stream
    _ <- safeFork $ sourceTChan ch' $$ sink
    -- up stream
    src $= tagFrame ident $$ sinkTChan ch

remoteClient :: Identity -> TChan ByteString -> TChan ByteString -> Application
remoteClient ident ch ch' src sink = do
    _ <- safeFork $ sourceTChan ch' $$ sink
    src $= tagFrame ident $$ sinkTChan ch

remoteServer :: TChan ByteString -> MVar TunnelMap -> Application
remoteServer ch tunnels src sink = do
    _ <- safeFork $ sourceTChan ch $$ sink
    src $= untagFrame $$ sinkTunnel
  where
    sinkTunnel = SinkData push close
    push (ident, _, buffer) = do
        ch' <- Lifted.modifyMVar tunnels $ \m ->
            case M.lookup ident m of
                Just ch' -> return (m, ch')
                Nothing -> do
                    ch' <- liftIO newTChanIO
                    _ <- safeFork $ liftIO $ runTCPClient
                            (ClientSettings proxyPort' proxyHost')
                            (remoteClient ident ch ch')
                    return (M.insert ident ch' m, ch')
        liftIO $ atomically $ writeTChan ch' buffer
        return $ Processing push close
    close = return ()

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["local", host, read -> port] -> do
            ch <- newTChanIO
            tunnels <- newIORef M.empty
            runTCPClient
                (ClientSettings port host)
                (localClient ch tunnels)

        ["remote", host, read -> port] -> do
            ch <- newTChanIO
            tunnels <- newMVar M.empty
            runTCPServer 
                (ServerSettings port (Just host))
                (remoteServer ch tunnels)

        _ -> putStrLn "./Main local|remote host port"
