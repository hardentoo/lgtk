{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
-- | Main LGtk interface.
module LGtk
    ( 
    -- * "Control.Category" re-export
      (.)
    , id

    -- * Lenses
    -- ** "Data.Lens.Common" module
    , module Data.Lens.Common

    -- ** Additional lenses
    , listLens
    , maybeLens

    -- ** Impure lenses
    , showLens

    -- * Restricted monads
    , HasReadPart (..)

    -- * References
    -- ** Basic operations
    , Reference
    , RefMonad
    , readRef
    , writeRef
    , lensMap
    , joinRef
    , unitRef

    -- ** Reference creation
    , ExtRef
    , Ref
    , extRef
    , newRef

    -- ** Derived constructs
    , ReadR
    , ReadRef
    , WriteRef
    , readRef'
    , undoTr
    , memoRead
    , memoWrite
    , modRef

    -- * Dynamic networks
    , EffRef
    , onChange

    , constSend -- TODO: eliminate
    , rEffect   -- TODO: eliminate
    , toReceive -- TODO: eliminate

    -- * I/O
    , EffIORef
    , getArgs
    , getProgName
    , lookupEnv
    , asyncWrite
    , fileRef

    -- * GUI

    -- ** Running
    , runWidget

    -- ** GUI descriptions
    , Widget
    , button
    , checkbox, combobox, entry
    , vcat, hcat
    , notebook
    , cell
    , action
    , module GUI.Gtk.Structures   -- TODO: eliminate

    -- ** Derived constructs
    , smartButton

    ) where

import Data.Maybe
import Control.Category
import Control.Concurrent
import Control.Monad
import Control.Monad.State
import Control.Monad.Trans.Identity
import Prelude hiding ((.), id)
import Data.Lens.Common

import Control.Monad.ExtRef hiding (liftWriteRef)
import qualified Control.Monad.ExtRef as ExtRef
import Control.Monad.Register
import Control.Monad.Register.Basic
import Control.Monad.EffRef
import GUI.Gtk.Structures hiding (Send, Receive, SendReceive, Widget)
import qualified GUI.Gtk.Structures as Gtk
import qualified GUI.Gtk.Structures.IO as Gtk
import Control.Monad.ExtRef.Pure
import Control.Monad.Restricted

type Widget m = Gtk.Widget (EffectM m) m

vcat :: [Widget m] -> Widget m
vcat = List Vertical

hcat :: [Widget m] -> Widget m
hcat = List Horizontal

smartButton
  :: (EffRef m, Eq a) =>
     ReadRef m String -> (a -> ReadRef m a) -> Ref m a -> Widget m
smartButton s f k =
    Button (rEffect s) (rEffect $ readRef k >>= \x -> liftM (/= x) $ f x)
             (toReceive $ \() -> runR (readRef k) >>= runR . f >>= writeRef k)

cell :: (EffRef m, Eq a) => Bool -> ReadRef m a -> (a -> m (Widget m)) -> Widget m
cell b r g = Cell (toSend b r) $ Action . g

button
    :: EffRef m
    => ReadRef m String
    -> ReadRef m (Maybe (WriteRef m ()))     -- ^ when the @Maybe@ value is @Nothing@, the button is inactive
    -> Widget m
button r fm = Button (rEffect r) (rEffect $ liftM isJust fm)
    (toReceive $ const $ runR fm >>= maybe (return ()) id)

checkbox :: EffRef m => Ref m Bool -> Widget m
checkbox r = Checkbox (rEffect (readRef r), register r)

combobox :: EffRef m => [String] -> Ref m Int -> Widget m
combobox ss r = Combobox ss (rEffect (readRef r), register r)

entry :: EffRef m => Ref m String -> Widget m
entry r = Entry (rEffect (readRef r), register r)

notebook :: EffRef m => [(String, Widget m)] -> Widget m
notebook xs = Action $ do
    currentPage <- newRef 0
    let f index (title, w) = (,) title $ cell True (liftM (== index) $ readRef currentPage) $ return . h where
           h False = hcat []
           h True = w
    return $ Notebook' (register currentPage) $ zipWith f [0..] xs

action :: EffRef m => m (Widget m) -> Widget m
action = Action

-- | Run an interface description
runWidget :: (forall m . EffIORef m => Widget m) -> IO ()
runWidget e = do
    post_ <- newRef' $ return ()
    let post' = runMorphD post_ . modify . flip (>>)
    ch <- newChan
    _ <- forkIO $ forever $ do
        join $ readChan ch
        join $ runMorphD post_ $ state $ \m -> (m, return ())
    Gtk.gtkContext $ \post ->
        runExtRef_ $ unliftIO $ \u ->
            evalRegister
                (        runIdentityT $
                    Gtk.runWidget u post' post e)
                (liftIO . writeChan ch . u)



