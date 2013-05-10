{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Control.Monad.Register.Basic
    ( Register
    , evalRegister
    ) where

import Control.Monad
import Control.Monad.Reader
import Control.Monad.Writer
import Control.Concurrent
import Data.IORef
import Data.List
import Prelude hiding ((.), id)

import Control.Monad.Restricted
import Control.Monad.Register
import Control.Monad.ExtRef

data MorphD m n = MorphD { unlift :: Morph m n }

data RegisterState n m = RegisterState
    { actions :: IO ()
    , sendEvent :: IO () -> IO ()
    , morph :: MorphD m IO
    , morphN :: MorphD n IO
    }

instance Monoid (IO ()) where
    mempty = return ()
    mappend = (>>)

newtype Register n m a = Register { runRegister :: ReaderT (RegisterState n m) (WriterT (IO (), Command -> IO ()) m) a }
    deriving (Functor, Monad, MonadIO)

instance (ExtRef m, n ~ WriteRef m) => ExtRef (Register n m) where

    type Ref (Register n m) = Ref m

    liftWriteRef = Register . liftWriteRef

    extRef r k a = Register $ extRef r k a

instance (MonadIO m, MMorph n) => MonadRegister (Register n m) where

    type PureM (Register n m) = n
    type EffectM (Register n m) = IO

    liftEffectM = Register . liftIO

    toReceive r int = do
        rr <- Register ask
        unreg <- liftEffectM $ int $ \a -> sendEvent rr $ do
            unlift (morphN rr) $ r a
            actions rr
        Register $ tell $ t2 unreg
        return ()

    toSend bb rb fb = do
        rr <- Register ask
        memoref <- liftIO $ newIORef (const $ return (), const $ return (), [])  -- unreg action, memo table, first item is the newest
        Register $ tell $ t1 $ do
            b <- unlift (morphN rr) $ runR rb
            let doit c (s1, ureg1) = do 
                    (s2, ureg2) <- unlift (morph rr) $ execWriterT $ runReaderT (runRegister c) rr
                    atomicModifyIORef' memoref $ \(_, _, memo) -> ((ureg1, ureg2, (b, (c, s1, s2, ureg1, ureg2)) : if bb then filter ((/= b) . fst) memo else []), ())
                    s1 >> s2
            join $ atomicModifyIORef' memoref $ \memo -> (,) memo $ case memo of
                (_, _, ((b', (_, s1, s2, _, _)): _)) | b' == b -> s1 >> s2
                (ur1, ur2, memo) -> do
                  ur1 $ if bb then Block else Kill
                  ur2 Kill
                  case (bb, filter ((== b) . fst) memo) of
                    (True, (_, (c, s1, _, ureg1, ureg2)): _) -> ureg1 Unblock >> doit c (s1, ureg1)
                    _ -> do
                        (c, s1) <- unlift (morph rr) $ runWriterT $ runReaderT (runRegister $ fb b) rr
                        doit c s1

t1 m = (m, const $ return ())
t2 m = (return (), m)

-- | evaluation with postponed actions
evalRegister :: (Monad n, MonadIO m) => Morph n IO -> Morph m IO -> ((IO () -> IO ()) -> Register n m a) -> m a
evalRegister morphN morph f = do
    post <- liftIO $ newIORef $ return ()
    let (Register m) = f $ \io -> atomicModifyIORef' post $ \m -> (m >> io, ())
    vx <- liftIO $ newIORef $ return ()
    ch <- liftIO newChan
    (a, reg) <- runWriterT $ runReaderT m $ RegisterState (join (readIORef vx) >> join (atomicModifyIORef' post (\m -> (return (), m)))) (writeChan ch) (MorphD morph) (MorphD morphN)
    liftIO $ writeIORef vx $ fst reg
    _ <- liftIO $ forkIO $ forever $ join $ readChan ch
    liftIO $ fst reg        -- needed?
    return a

