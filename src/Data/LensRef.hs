{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# OPTIONS_HADDOCK prune #-}
module Data.LensRef
    (
    -- * Core

    -- ** References
      Reference (..)
    , RefWriterOf
    , RefWriter
    , RefSimple

    , MonadRefReader (..)
    , MonadRefWriter (..)

    -- ** Reference creation
    , ExtRef (..)
    , Ref
    , ReadRef
    , WriteRef

    -- ** Dynamic networks
    , EffRef (..)
    , Command (..)

    -- * Derived constructs
    , modRef
    , toReceive1
    , rEffect
    , iReallyWantToModify
--    , undoTr

    , EqReference (..)
    , EqRef
    , hasEffect
    , eqRef
    , newEqRef
    , toRef
{-
    , CorrRef
    , corrRef
    , fromCorrRef
    , correction
-}
    ) where


import Control.Monad (liftM, join)
import Control.Lens (Lens', lens, set, (^.))

--------------------------------


{- |
Type class for references which can be joined and on which lenses can be applied.

The join operation is 'join' from "Control.Monad":
If @(r :: RefReader r (RefSimple r a))@ then @(join r :: RefSimple r a)@.
This is possible because reference operations work with @(RefReader r (r a))@ instead
of just @(r a)@. For more compact type signatures, @(RefReader r (r a))@ is called @(RefSimple r a)@.
-}
class (MonadRefWriter (RefWriter r), MonadRefReader (RefReader r), ReadRef (RefReader r) ~ RefReader r) => Reference r where

    {- | unit reference

    Laws:

    prop> writeRef unitRef () >> m  =  m
    -}
    unitRef :: RefSimple r ()

    {- | Apply a lens on a reference.
    -}
    lensMap :: Lens' a b -> RefSimple r a -> RefSimple r b

    {- | Associated reader monad.

    @(RefReader m)@ is ismoroprhic to @('Reader' x)@ for some @x@.
    Laws which ensures this isomorphism (@(r :: RefReader m a)@ is arbitrary):

    prop> r >> return ()  =  return ()
    prop> liftM2 (,) r r  =  liftM (\a -> (a, a)) r

    See also <http://stackoverflow.com/questions/16123588/what-is-this-special-functor-structure-called>
    -}
    type RefReader r :: * -> *

    {- | Reference read.

    Laws:

    prop> readRef r >> return ())  =  return ()
    -}
    readRefSimple  :: RefSimple r a -> RefReader r a

    {- | Reference write.

    Properties derived from the set-get, get-set and set-set laws for lenses:

    prop> readRef r >>= writeRef r  =  return ()
    prop> writeRef r a >> readRef r)  =  return a
    prop> writeRef r a >> writeRef r a')  =  writeRef r a'
    -}
    writeRefSimple :: RefSimple r a -> a -> RefWriter r ()


data family RefWriterOf (m :: * -> *) a :: *

{- |
There are two associated types of a reference, 'RefReader' and 'RefWriter' which determines each-other.
This is implemented by putting only 'RefReader' into the 'Reference' class and
adding a @RefWriterOf@ data family outside of 'Reference'.

@RefWriterOf@ is hidden from the documentation because you never need it explicitly.
-}
type RefWriter m = RefWriterOf (RefReader m)

-- | Reference wrapped into a RefReader monad. See the documentation of 'Reference'.
type RefSimple r a = RefReader r (r a)

infixr 8 `lensMap`

-- | TODO
class Monad m => MonadRefReader m where

    type BaseRef m :: * -> *

    {- | @ReadRef@ lifted to the reference creation class.

    Note that we do not lift @WriteRef@ to the reference creation class, which a crucial restriction
    in the LGtk interface; this is a feature.
    -}
    liftReadRef :: ReadRef m a -> m a

    {- | @readRef@ lifted to the reference creation class.

    @readRef@ === @liftReadRef . readRefSimple@
    -}
    readRef :: (Reference r, ReadRef m ~ RefReader r) => RefSimple r a -> m a
    readRef = liftReadRef . readRefSimple


-- | TODO
type ReadRef m = RefReader (BaseRef m)

-- | TODO
type WriteRef m = RefWriter (BaseRef m)

-- | TODO
type Ref m a = RefSimple (BaseRef m) a



-- | TODO
class MonadRefReader m => MonadRefWriter m where

    liftWriteRef :: WriteRef m a -> m a

    writeRef :: (Reference r, RefReader r ~ ReadRef m) => RefSimple r a -> a -> m ()
    writeRef r = liftWriteRef . writeRefSimple r






{- | Monad for reference creation. Reference creation is not a method
of the 'Reference' type class to make possible to
create the same type of references in multiple monads.

@(Extref m) === (StateT s m)@, where 's' is an extendible state.

For basic usage examples, look into the source of @Data.LensRef.Pure.Test@.
-}
class (Monad m, Reference (BaseRef m), MonadRefReader m) => ExtRef m where

    {- | Reference creation by extending the state of an existing reference.

    Suppose that @r@ is a reference and @k@ is a lens.

    Law 1: @extRef@ applies @k@ on @r@ backwards, i.e. 
    the result of @(extRef r k a0)@ should behaves exactly as @(lensMap k r)@.

     *  @(liftM (k .) $ extRef r k a0)@ === @return r@

    Law 2: @extRef@ does not change the value of @r@:

     *  @(extRef r k a0 >> readRef r)@ === @(readRef r)@

    Law 3: Proper initialization of newly defined reference with @a0@:

     *  @(extRef r k a0 >>= readRef)@ === @(readRef r >>= set k a0)@
    -}
    extRef :: Ref m b -> Lens' a b -> a -> m (Ref m a)

    {- | @newRef@ extends the state @s@ in an independent way.

    @newRef@ === @extRef unitRef (lens (const ()) (const id))@
    -}
    newRef :: a -> m (Ref m a)
    newRef = extRef unitRef $ lens (const ()) (flip $ const id)


    {- | Lazy monadic evaluation.
    In case of @y <- memoRead x@, invoking @y@ will invoke @x@ at most once.

    Laws:

     *  @(memoRead x >> return ())@ === @return ()@

     *  @(memoRead x >>= id)@ === @x@

     *  @(memoRead x >>= \y -> liftM2 (,) y y)@ === @liftM (\a -> (a, a)) y@

     *  @(memoRead x >>= \y -> liftM3 (,) y y y)@ === @liftM (\a -> (a, a, a)) y@

     *  ...
    -}
    memoRead :: m a -> m (m a)

    memoWrite :: Eq b => (b -> m a) -> m (b -> m a)

    future :: (ReadRef m a -> m a) -> m a


-- | Monad for dynamic actions
class (ExtRef m, Monad (EffectM m), MonadRefWriter (Modifier m), ExtRef (Modifier m), BaseRef (Modifier m) ~ BaseRef m) => EffRef m where

    type EffectM m :: * -> *

    liftEffectM :: EffectM m a -> m a

    {- |
    Let @r@ be an effectless action (@ReadRef@ guarantees this).

    @(onChange init r fmm)@ has the following effect:

    Whenever the value of @r@ changes (with respect to the given equality),
    @fmm@ is called with the new value @a@.
    The value of the @(fmm a)@ action is memoized,
    but the memoized value is run again and again.

    The boolean parameter @init@ tells whether the action should
    be run in the beginning or not.

    For example, let @(k :: a -> m b)@ and @(h :: b -> m ())@,
    and suppose that @r@ will have values @a1@, @a2@, @a3@ = @a1@, @a4@ = @a2@.

    @onChange True r $ \\a -> k a >>= return . h@

    has the effect

    @k a1 >>= \\b1 -> h b1 >> k a2 >>= \\b2 -> h b2 >> h b1 >> h b2@

    and

    @onChange False r $ \\a -> k a >>= return . h@

    has the effect

    @k a2 >>= \\b2 -> h b2 >> k a1 >>= \\b1 -> h b1 >> h b2@
    -}
    onChange_
        :: Eq b
        => ReadRef m b
        -> b -> (b -> c)
        -> (b -> b -> c -> m (c -> m c))
        -> m (ReadRef m c)

    onChange :: Eq a => ReadRef m a -> (a -> m (m b)) -> m (ReadRef m b)
    onChange r f = onChange_ r undefined undefined $ \b _ _ -> liftM (\x _ -> x) $ f b

    onChangeSimple :: Eq a => ReadRef m a -> (a -> m b) -> m (ReadRef m b)
    onChangeSimple r f = onChange r $ return . f

    data Modifier m a :: *

    liftModifier :: m a -> Modifier m a

    toReceive :: Functor f => f (Modifier m ()) -> (Command -> EffectM m ()) -> m (f (EffectM m ()))

-- | TODO
data Command = Kill | Block | Unblock deriving (Eq, Ord, Show)





-------------- derived constructs


-- | TODO
toReceive1 :: EffRef m => Modifier m () -> (Command -> EffectM m ()) -> m (EffectM m ())
toReceive1 m c = do
    f <- toReceive (const m) c
    return $ f ()

-- | TODO
rEffect  :: (EffRef m, Eq a) => ReadRef m a -> (a -> EffectM m b) -> m (ReadRef m b)
rEffect r f = onChangeSimple r $ liftEffectM . f

-- | @modRef r f@ === @readRef r >>= writeRef r . f@
modRef :: (MonadRefWriter m, Reference r, RefReader r ~ ReadRef m) => RefSimple r a -> (a -> a) -> m ()
r `modRef` f = readRef r >>= writeRef r . f


-- | TODO
iReallyWantToModify :: EffRef m => Modifier m () -> m ()
iReallyWantToModify r = do
    x <- toReceive1 r $ const $ return ()
    liftEffectM x




{- | References with inherent equivalence.

-}
class Reference r => EqReference r where
    valueIsChanging :: RefSimple r a -> RefReader r (a -> Bool)

{- | @hasEffect r f@ returns @False@ iff @(modRef m f)@ === @(return ())@.

@hasEffect@ is correct only if @eqRef@ is applied on a pure reference (a reference which is a pure lens on the hidden state).

@hasEffect@ makes defining auto-sensitive buttons easier, for example.
-}
hasEffect
    :: EqReference r
    => RefSimple r a
    -> (a -> a)
    -> RefReader r Bool
hasEffect r f = do
    a <- readRef r
    ch <- valueIsChanging r
    return $ ch $ f a


-- | TODO
data EqBaseRef r a = EqBaseRef (r a) (a -> Bool{-changed-})

{- | References with inherent equivalence.

@EqRef r a@ === @RefReader r (exist b . Eq b => (Lens' b a, r b))@

As a reference, @(m :: EqRef r a)@ behaves as

@join $ liftM (uncurry lensMap) m@
-}
type EqRef r a = RefReader r (EqBaseRef r a)

{- | @EqRef@ construction.
-}
eqRef :: (Reference r, Eq a) => RefSimple r a -> EqRef r a
eqRef r = do
    a <- readRef r
    r_ <- r
    return $ EqBaseRef r_ $ (/= a)

-- | TODO
newEqRef :: (ExtRef m, Eq a) => a -> m (EqRef (BaseRef m) a) 
newEqRef = liftM eqRef . newRef

{- | An @EqRef@ is a normal reference if we forget about the equality.

@toRef m@ === @join $ liftM (uncurry lensMap) m@
-}
toRef :: Reference r => EqRef r a -> RefSimple r a
toRef m = m >>= \(EqBaseRef r _) -> return r

instance Reference r => EqReference (EqBaseRef r) where
    valueIsChanging m = do
        EqBaseRef _r k <- m
        return k

instance Reference r => Reference (EqBaseRef r) where

    type (RefReader (EqBaseRef r)) = RefReader r

    readRefSimple = readRef . toRef

    writeRefSimple = writeRefSimple . toRef

    lensMap l m = do
        a <- readRef m
        EqBaseRef r k <- m
        lr <- lensMap l $ return r
        return $ EqBaseRef lr $ \b -> k $ set l b a

    unitRef = eqRef unitRef

{-
data CorrBaseRef r a = CorrBaseRef (r a) (a -> Maybe a{-corrected-})

type CorrRef r a = RefReader r (CorrBaseRef r a)

instance Reference r => Reference (CorrBaseRef r) where

    type (RefReader (CorrBaseRef r)) = RefReader r

    readRef = readRef . fromCorrRef

    writeRefSimple = writeRefSimple . fromCorrRef

    lensMap l m = do
        a <- readRef m
        CorrBaseRef r k <- m
        lr <- lensMap l $ return r
        return $ CorrBaseRef lr $ \b -> fmap (^. l) $ k $ set l b a

    unitRef = corrRef (const Nothing) unitRef

fromCorrRef :: Reference r => CorrRef r a -> RefSimple r a
fromCorrRef m = m >>= \(CorrBaseRef r _) -> return r

corrRef :: Reference r => (a -> Maybe a) -> RefSimple r a -> CorrRef r a
corrRef f r = do
    r_ <- r
    return $ CorrBaseRef r_ f

correction :: Reference r => CorrRef r a -> RefReader r (a -> Maybe a)
correction r = do
    CorrBaseRef _ f <- r
    return f
-}


