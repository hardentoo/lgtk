{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds #-}
module LGtk.Demos.TEditor where

import Control.Monad
import Prelude hiding ((.), id)

import LGtk
import LGtk.ADTEditor

-- | Binary tree shapes
data T
    = Leaf
    | Node T T
        deriving Show

-- | Lens for @T@
tLens :: Lens (Bool, (T, T)) T
tLens = lens get set where
    get (False, _)     = Leaf
    get (True, (l, r)) = Node l r
    set Leaf (_, x)   = (False, x)
    set (Node l r) _ = (True, (l, r))

-- | @ADTLens@ instance for @T@
instance ADTLens T where
    type ADTEls T = Cons T (Cons T Nil)
    adtLens = ([("Leaf",[]),("Node",[0,1])], ElemsCons Leaf (ElemsCons Leaf ElemsNil), lens get set) where
        get :: (Int, Elems (ADTEls T)) -> T
        get (0, _)     = Leaf
        get (1, ElemsCons l (ElemsCons r ElemsNil)) = Node l r
        set :: T -> (Int, Elems (ADTEls T)) -> (Int, Elems (ADTEls T))
        set Leaf (_, x)   = (0, x)
        set (Node l r) _ = (1, ElemsCons l (ElemsCons r ElemsNil))

-- | @T@ editor with comboboxes, as an ADTEditor
tEditor1 :: (MonadRegister m, ExtRef m, Inner m ~ Inner' m) => I m
tEditor1 = Action $ newRef Leaf >>= adtEditor

-- | @T@ editor with checkboxes, given directly
tEditor2 :: (MonadRegister m, ExtRef m, Inner m ~ Inner' m) => I m
tEditor2 = Action $ liftM editor $ newRef Leaf  where

    editor r = Action $ do
        q <- extRef r tLens (False, (Leaf, Leaf))
        return $ hcat
            [ checkbox $ fstLens % q
            , cell True $ IC (liftM fst $ readRef q) $ \b -> return $ vcat $ 
                  [ editor $ fstLens . sndLens % q | b ]
               ++ [ editor $ sndLens . sndLens % q | b ]
            ]

-- | Another @T@ editor with checkboxes, given directly
tEditor3 :: (MonadRegister m, ExtRef m, Inner m ~ Inner' m) => IRef m T -> C m (I m)
tEditor3 = liftM Action . memoRead . editor' where
    editor' r = do
        q <- extRef r tLens (False, (Leaf, Leaf))
        t1 <- tEditor3 $ fstLens . sndLens % q
        t2 <- tEditor3 $ sndLens . sndLens % q
        return $ hcat
            [ checkbox $ fstLens % q
            , cell True $ IC (liftM fst $ readRef q) $ \b -> return $ vcat $ [t1 | b] ++ [t2 | b]
            ]

