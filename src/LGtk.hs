{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
-- | Main LGtk interface.
module LGtk
    (
    -- * References

    -- ** Reference modifying monad
      MonadRefState (..)

    -- ** Reference operations
    , Reference, MRef
    , RefState
    , RefReader
    , readRef
    , writeRef
    , lensMap
    , join
    , unitRef

    -- ** Reference creation
    , ExtRef
    , Ref, RefCore
    , extRef
    , newRef
    , ReadRef
    , WriteRef
    , liftReadRef

    -- ** Derived constructs
    , modRef
    , readRef'
    , memoRead
    , undoTr

    , EqReference (..)
    , EqRef
    , eqRef
    , newEqRef
    , toRef

    -- * Dynamic networks
    , EffRef
    , onChange

    -- * I/O
    , SafeIO
    , getArgs
    , getProgName
    , lookupEnv

    , EffIORef
    , asyncWrite
    , putStr_
    , getLine_
    , fileRef

    -- ** Derived constructs
    , putStrLn_

    -- * GUI

    -- ** Running
    , Widget
    , runWidget
--    , runWidget'

    -- ** GUI descriptions
    , label
    , checkbox
    , combobox
    , entry
    , vcat
    , hcat
    , button_
    , Color (..)
    , notebook
    , cell_
    , action
    , canvas
    , Dia
    , MouseEvent (..)
    , MousePos (..)
    , Modifier
    , KeyVal
    , keyName
    , keyToChar
    , ScrollDirection (..)
    , hscale

    -- ** Derived constructs
    , empty
    , entryShow
    , button
    , smartButton
    , cell
    , cellNoMemo

    -- ** Experimental
    , button__

    -- ** Utils
    , showLens
    , listLens

    ) where

import Data.Maybe
import Data.Monoid
import Control.Monad
import Control.Lens

import Control.Monad.ExtRef
import Control.Monad.EffRef
import GUI.Gtk.Structures hiding (Send, Receive, SendReceive, Widget)
import qualified GUI.Gtk.Structures as Gtk
import qualified GUI.Gtk.Structures.IO as Gtk
import Control.Monad.Restricted


{- |
Gtk widget descriptions.
Construction of a @(w :: forall m . EffIORef m => Widget m)@ value is side-effect free,
side-effects happen at running @('runWidget' w)@.

@Widget@ should be abstract data type, but it is also safe to keep it as a type synonym because
the operations of the revealed implementation are hidden.
-}
type Widget m = Gtk.Widget (EffectM m) m (CallbackM m)

--type SyntWidget = Widget (SyntEffIORef X)

{- |
Run a Gtk widget description.

The widget is shown in a window and the thread enters into the Gtk event cycle.
It leaves the event cycle when the window is closed.
-}
runWidget :: (forall m . EffIORef m => Widget m) -> IO ()
runWidget = Gtk.runWidget

-- | Vertical composition of widgets.
vcat :: Monad m => [Widget m] -> Widget m
vcat = return . List Vertical

-- | Horizontal composition of widgets.
hcat :: Monad m => [Widget m] -> Widget m
hcat = return . List Horizontal

-- | Empty widget.
empty :: Monad m => Widget m
empty = hcat []

-- | Dynamic label.
label :: EffRef m => ReadRef m String -> Widget m
label = return . Label . rEffect True

-- | Low-level button with changeable background color.
button__
    :: EffRef m
    => ReadRef m String     -- ^ dynamic label of the button
    -> ReadRef m Bool       -- ^ the button is active when this returns @True@
    -> ReadRef m Color      -- ^ dynamic background color
    -> WriteRef m ()        -- ^ the action to do when the button is pressed
    -> Widget m
button__ r x c y = return $ Button (rEffect True r) (rEffect True x) (rEffect True c) (toReceive $ \() -> y)

-- | Low-level button.
button_
    :: EffRef m
    => ReadRef m String     -- ^ dynamic label of the button
    -> ReadRef m Bool       -- ^ the button is active when this returns @True@
    -> WriteRef m ()        -- ^ the action to do when the button is pressed
    -> Widget m
button_ r x y = return $ Button (rEffect True r) (rEffect True x) (const $ return ()) (toReceive $ \() -> y)

button
    :: EffRef m
    => ReadRef m String     -- ^ dynamic label of the button
    -> ReadRef m (Maybe (WriteRef m ()))     -- ^ when the @Maybe@ value is @Nothing@, the button is inactive
    -> Widget m
button r fm = button_ r (liftM isJust fm) (liftRefStateReader fm >>= maybe (return ()) id)



smartButton
    :: (EffRef m, EqReference r, RefState r ~ RefState (RefCore m)) 
    => ReadRef m String     -- ^ dynamic label of the button
    -> MRef r a              -- ^ underlying reference
    -> (a -> a)   -- ^ The button is active when this function is not identity on value of the reference. When the button is pressed, the value of the reference is modified with this function.
    -> Widget m
smartButton s r f
    = button_ s (hasEffect r f) (modRef r f)

-- | Checkbox.
checkbox :: EffRef m => Ref m Bool -> Widget m
checkbox r = return $ Checkbox (rEffect True (readRef r), toReceive $ writeRef r)

-- | Simple combo box.
combobox :: EffRef m => [String] -> Ref m Int -> Widget m
combobox ss r = return $ Combobox ss (rEffect True (readRef r), toReceive $ writeRef r)

-- | Text entry.
entry :: (EffRef m, Reference r, RefState r ~ RefState (RefCore m))  => MRef r String -> Widget m
entry r = return $ Entry (rEffect True (readRef r), toReceive $ writeRef r)

-- | Text entry.
entryShow :: (EffRef m, Show a, Read a, Reference r, RefState r ~ RefState (RefCore m)) => MRef r a -> Widget m
entryShow r = entry $ showLens `lensMap` r

{- | Notebook (tabs).

The tabs are created lazily.
-}
notebook :: EffRef m => [(String, Widget m)] -> Widget m
notebook xs = do
    currentPage <- newRef 0
    let f index (title, w) = (,) title $ cell (liftM (== index) $ readRef currentPage) $ \b -> case b of
           False -> hcat []
           True -> w
    return $ Notebook' (toReceive $ writeRef currentPage) $ zipWith f [0..] xs

{- | Dynamic cell.

The monadic action for inner widget creation is memoised in the first monad layer.
-}
cell_ :: (EffRef m, Eq a) => ReadRef m a -> (forall x . (Widget m -> m x) -> a -> m (m x)) -> Widget m
cell_ r f = return $ Cell (onChange True r) f

{- | Dynamic cell.

The inner widgets are memoised.
-}
cell :: (EffRef m, Eq a) => ReadRef m a -> (a -> Widget m) -> Widget m
cell r m = cell_ r $ \mk -> liftM return . mk . m

{- | Dynamic cell.

The inner widgets are not memoised.
-}
cellNoMemo :: (EffRef m, Eq a) => ReadRef m a -> (a -> Widget m) -> Widget m
cellNoMemo r m = cell_ r $ \mk -> return . mk . m

-- | @action@ makes possible to do any 'EffRef' action while creating the widget.
action :: EffRef m => m (Widget m) -> Widget m
action = join

canvas :: (EffRef m, Eq b, Monoid a) => Int -> Int -> Double -> (MouseEvent a -> WriteRef m ()) -> ReadRef m b -> (b -> Dia a) -> Widget m
canvas w h sc me r f = return $ Canvas w h sc (toReceive me) (rEffect True r) f
 -- = cellNoMemo r $ Canvas_ w h sc . f  -- Canvas f $ rEffect True r

hscale :: (EffRef m) => Double -> Double -> Double -> Ref m Double -> Widget m
hscale a b c r = return $ Scale a b c (rEffect True $ readRef r, toReceive $ writeRef r)

showLens :: (Show a, Read a) => Lens' a String
showLens = lens show $ \def s -> maybe def fst $ listToMaybe $ reads s

listLens :: Lens' (Bool, (a, [a])) [a]
listLens = lens get set where
    get (False, _) = []
    get (True, (l, r)) = l: r
    set (_, x) [] = (False, x)
    set _ (l: r) = (True, (l, r))
