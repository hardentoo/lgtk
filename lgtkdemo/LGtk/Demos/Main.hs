{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
module LGtk.Demos.Main
    ( main
    ) where

import Numeric
import Data.Maybe (isJust)
import Control.Lens hiding ((#))
import Control.Monad
import Control.Monad.Fix
import Diagrams.Prelude hiding (vcat, hcat, Point, Start, adjust, value, interval, tri)
import qualified Diagrams.Prelude as D

import LGtk

import LGtk.Demos.Tri
import LGtk.Demos.IntListEditor
import LGtk.Demos.TEditor
import LGtk.Demos.Maze

main :: IO ()
main = runWidget mainWidget

mainWidget :: Widget
mainWidget = notebook
    [ (,) "Simple" $ notebook

--      , (,) "Hello" $ label $ pure "Hello World!"

        [ (,) "Counters" $ notebook

            [ (,) "Unbounded" $ do
                c <- fmap withEq $ extendState (0 :: Int)
                vcat
                    [ label $ fmap show $ value c
                    , hcat
                        [ smartButton (pure "+1") c (+1)
                        , smartButton (pure "-1") c (+(-1))
                        ]
                    ]

            , (,) "1..3" $ do
                c <- fmap withEq $ extendState (1 :: Int)
                vcat
                    [ label $ fmap show $ value c
                    , hcat
                        [ smartButton (pure "+1") c $ min 3 . (+1)
                        , smartButton (pure "-1") c $ max 1 . (+(-1))
                        ]
                    ]

            , (,) "a..b" $ do
                ab <- extendState (1 :: Int, 3)
                let (a, b) = interval ab
                c <- counter 0 ab
                vcat
                    [ label $ fmap show $ value c
                    , hcat
                        [ smartButton (pure "+1") c (+1)
                        , smartButton (pure "-1") c (+(-1))
                        ]
                    , hcat [ label $ pure "min", entryShow a ]
                    , hcat [ label $ pure "max", entryShow b ]
                    ]

            ]

{-
        , (,) "Buttons" $ do
            x <- extendState (0 :: Int)
            let is = [0 :: Double, 0.5, 1]
                colorlist = tail $ liftA3 sRGB is is is
                f n = colorlist !! (n `mod` length colorlist)
            button__ (pure "Push") (pure True) (fmap f $ value x) $ adjust x (+1)

        , (,) "Tabs" $ notebook

            [ (,) "TabSwitch" $ do
                x <- extendState "a"
                let w = vcat [ label $ value x, entry x ]
                notebook
                    [ (,) "T1" w
                    , (,) "T2" w
                    ]

            ]
-}

        , (,) "Tri" tri

        , (,) "T-Editor" $ notebook

            [ (,) "Version 1" $ do
                t <- extendState $ iterate (Node Leaf) Leaf !! 10
                hcat
                    [ canvas 200 200 20 (const $ pure ()) Nothing (value t) $
                        \x -> tPic 0 x # lwL 0.05 # D.value () # translate (r2 (0,10))
                    , tEditor3 t
                    ]

            , (,) "Version 2" tEditor1
            ]

        , (,) "Notebook" $ notebook

            [ (,) "Version 2" $ do
                buttons <- extendState ("",[])
                let ctrl = entry $ lens fst (\(_,xs) x -> ("",x:xs)) `lensMap` buttons
                    h b = do
                        q <- extendStateWith b listLens (False, ("", []))
                        cell (fmap fst $ value q) $ \bb -> case bb of
                            False -> empty
                            _ -> do
                                vcat $ reverse
                                    [ h $ _2 . _2 `lensMap` q
                                    , hcat
                                        [ button (pure "Del") $ pure $ Just $ adjust b tail
                                        , label $ value $ _2 . _1 `lensMap` q
                                        ]
                                    ]
                vcat $ [ctrl, h $ _2 `lensMap` buttons]

            , (,) "Version 1" $ do
                buttons <- extendState ("",[])
                let h i b = hcat
                       [ label $ pure b
                       , button (pure "Del") $ pure $ Just $ adjust (_2 `lensMap` buttons) $ \l -> take i l ++ drop (i+1) l
                       ]
                    set (a,xs) x
                        | a /= x = ("",x:xs)
                        | otherwise = (a,xs)
                vcat
                    [ entry $ lens fst set `lensMap` buttons
                    , cell (fmap snd $ value buttons) $ vcat . zipWith h [0..]
                    ]

            ]

        ]

    , (,) "Canvas" $ notebook

        [ (,) "NotReactive" $ notebook

            [ (,) "Dynamic" $ do

                r <- extendState (3 :: Double)
                vcat
                    [ canvas 200 200 12 (const $ pure ()) Nothing (value r) $
                        \x -> circle x # lwL 0.05 # fc blue # D.value ()
                    , hcat
                        [ hscale 0.1 5 0.05 r
                        , label (fmap (("radius: " ++) . ($ "") . showFFloat (Just 2)) $ value r)
                        ]
                    ]

            , (,) "Animation" $ do

                fps <- extendState (50 :: Double)
                speed <- extendState (1 :: Double)
                phase <- extendState (0 :: Double)
                t <- extendState 0
                _ <- onChangeEq (value phase) $ \x -> do
                    s <- value speed
                    f <- value fps
                    asyncWrite (round $ 1000000 / f) $ write phase (x + 2 * pi * s / f)
                vcat
                    [ canvas 200 200 10 (const $ pure ()) Nothing (liftA2 (,) (value t) (value phase)) $
                        \(t,x) -> (case t of
                            0 -> circle (2 + 1.5*sin x)
                            1 -> circle 1 # translate (r2 (3,0)) # rotate ((-x) @@ rad)
                            2 -> rect 6 6 # rotate ((-x) @@ rad)
                            3 -> mconcat [circle (i'/10) # translate (r2 (i'/3, 0) # rotate ((i') @@ rad)) | i<-[1 :: Int ..10], let i' = fromIntegral i] # rotate ((-x) @@ rad)
                            4 -> mconcat [circle (i'/10) # translate (r2 (i'/3, 0) # rotate ((x/i') @@ rad)) | i<-[1 :: Int ..10], let i' = fromIntegral i]
                            ) # lwL 0.05 # fc blue # D.value ()
                    , combobox ["Pulse","Rotate","Rotate2","Spiral","Spiral2"] t
                    , hcat
                        [ hscale 0.1 5 0.1 speed
                        , label (fmap (("freq: " ++) . ($ "") . showFFloat (Just 2)) $ value speed)
                        ]
                    , hcat
                        [ hscale 1 100 1 fps
                        , label (fmap (("fps: " ++) . ($ "") . showFFloat (Just 2)) $ value fps)
                        ]
                    ]

            ]

        , (,) "Reactive" $ notebook

            [ (,) "ColorChange" $ do
                phase <- extendState (0 :: Double)
                col <- extendState True
                _ <- onChangeEq (value phase) $ \x -> do
                    let s = 0.5 :: Double
                    let f = 50 :: Double
                    asyncWrite (round $ 1000000 / f) $ write phase (x + 2 * pi * s / f)
                let handler (Click (MousePos _ l), _) = when (not $ null l) $ adjust col not
                    handler _ = pure ()
                vcat
                    [ canvas 200 200 10 handler Nothing (liftA2 (,) (value col) (value phase)) $
                        \(c,x) -> circle 1 # translate (r2 (3,0)) # rotate ((-x) @@ rad) # lwL 0.05 # fc (if c then blue else red) # D.value [()]
                    , label $ pure "Click on the circle to change color."
                    ]

            , (,) "Enlarge" $ do
                phase <- extendState (0 :: Double)
                col <- extendState 1
                _ <- onChangeEq (value phase) $ \x -> do
                    let s = 0.5 :: Double
                    let f = 50 :: Double
                    asyncWrite (round $ 1000000 / f) $ do
                        write phase (x + 2 * pi * s / f)
                        adjust col $ max 1 . (+(- 5/f))
                let handler (Click (MousePos _ l), _) = when (not $ null l) $ adjust col (+1)
                    handler _ = pure ()
                vcat
                    [ canvas 200 200 10 handler Nothing (liftA2 (,) (value col) (value phase)) $
                        \(c,x) -> circle c # translate (r2 (3,0)) # rotate ((-x) @@ rad) # lwL 0.05 # fc blue # D.value [()]
                    , label $ pure "Click on the circle to temporarily enlarge it."
                    ]

                , (,) "Chooser" $ do
                i <- extendState (0 :: Int, 0 :: Rational)
                let i1 = _1 `lensMap` i
                    i2 = _2 `lensMap` i
                _ <- onChangeEq (value i) $ \(i,d) -> do
                    let dd = fromIntegral i - d
                    if dd == 0
                      then pure ()
                      else do
                        let s = 2 :: Rational
                        let f = 25 :: Rational
                        asyncWrite (round $ 1000000 / f) $ do
                            write i2 $ d + signum dd * min (abs dd) (s / f)
                let keyh (SimpleKey Key'Left)  = adjust i1 pred >> pure True
                    keyh (SimpleKey Key'Right) = adjust i1 succ >> pure True
                    keyh _ = pure False
                vcat
                    [ canvas 200 200 10 (const $ pure ()) (Just keyh) (value i2) $
                        \d -> text "12345" # translate (r2 (realToFrac d, 0)) # scale 2 # D.value ()
                    , label $ fmap show $ value i1
                    ]

            ]

        , (,) "InCanvas" $ notebook

            [ (,) "Widgets" $ inCanvasExample

            , (,) "Recursive" $ inCanvas 800 600 30 mainWidget

            ]

        ]

    , (,) "System" $ notebook

    {-
        , (,) "Accumulator" $ do
            x <- extendState (0 :: Integer)
            y <- onChangeAcc (value x) 0 (const 0) $ \x _ y -> Left $ pure $ x+y
            hcat
                [ entryShow x
                , label $ fmap show y
                ]
    -}
        [ (,) "Async" $ do
            ready <- extendState True
            delay <- extendState (1.0 :: Double)
            _ <- onChangeEq (value ready) $ \b -> case b of
                True -> pure ()
                False -> do
                    d <- value delay
                    asyncWrite (ceiling $ 1000000 * d) $ write ready True
            vcat
                [ hcat [ entryShow delay, label $ pure "sec" ]
                , primButton (flip fmap (value delay) $ \d -> "Start " ++ show d ++ " sec computation")
                          (value ready)
                          Nothing
                          (write ready False)
                , label $ fmap (\b -> if b then "Ready." else "Computing...") $ value ready
                ]

        , (,) "Timer" $ do
            t <- extendState (0 :: Int)
            _ <- onChangeEq (value t) $ \ti -> asyncWrite 1000000 $ write t $ 1 + ti
            vcat
                [ label $ fmap show $ value t
                ]

        , (,) "System" $ notebook

            [ (,) "Args" $ getArgs >>= \args -> label $ pure $ unlines args

            , (,) "ProgName" $ getProgName >>= \args -> label $ pure args

            , (,) "Env" $ do
                v <- extendState "HOME"
                lv <- onChangeEq (value v) $ fmap (maybe "Not in env." show) . lookupEnv
                vcat
                    [ entry v
                    , label lv
                    ]

            , (,) "Std I/O" $ let
                put = do
                    x <- extendState Nothing
                    _ <- onChangeEq (value x) $ maybe (pure ()) putStrLn_
                    hcat 
                        [ label $ pure "putStrLn"
                        , entry $ iso (maybe "" id) Just `lensMap` x
                        ]
                get = do
                    ready <- extendState $ Just ""
                    _ <- onChangeEq (fmap isJust $ value ready) $ \b -> 
                        when (not b) $ getLine_ $ write ready . Just
                    hcat 
                        [ primButton (pure "getLine") (fmap isJust $ value ready) Nothing $ write ready Nothing
                        , label $ fmap (maybe "<<<waiting for input>>>" id) $ value ready
                        ]
               in vcat [ put, put, put, get, get, get ]
            ]
        ]

    , (,) "Complex" $ notebook

        [ (,) "ListEditor" $ do
            state <- fileRef "intListEditorState.txt"
            list <- extendStateWith (justLens "" `lensMap` state) showLens []
            settings <- fileRef "intListEditorSettings.txt"
            range <- extendStateWith (justLens "" `lensMap` settings) showLens True
            intListEditor (0 :: Integer, True) 15 list range

        , (,) "Maze" $ mazeGame

        ]

{-
    , (,) "Csaba" $ notebook

        [ (,) "#1" $ do
            name <- extendState "None"
            buttons <- extendState []
            let ctrl = hcat
                    [ label $ value name
                    , button (pure "Add") $ pure $ Just $ do
                        l <- value buttons
                        let n = "Button #" ++ (show . length $ l)
                        write buttons $ n:l
                    ]
                f n = vcat $ map g n 
                g n = button (pure n) (pure . Just $ write name n)
            vcat $ [ctrl, cell (value buttons) f]

        , (,) "#2" $ do
            name <- extendState "None"
            buttons <- extendState []
            let ctrl = hcat
                    [ label $ value name
                    , button (pure "Add") $ pure $ Just $ do
                        l <- value buttons
                        let n = "Button #" ++ (show . length $ l)
                        write buttons $ l ++ [n]
                    ]
                h b = do
                    q <- extendStateWith b listLens (False, ("", []))
                    cell (fmap fst $ value q) $ \b -> case b of
                        False -> empty
                        _ -> do
                            na <- value $ _2 . _1 `lensMap` q
                            vcat $ reverse
                                [ h $ _2 . _2 `lensMap` q
                                , hcat [ button (pure na) $ pure $ Just $ write name na, entry $ _2 . _1 `lensMap` q ]
                                ]
            vcat $ [ctrl, h buttons]

        ]
-}    
    ]

tPic :: Int -> T -> Dia Any
tPic _ Leaf = circle 0.5 # fc blue
tPic i (Node a b) = tPic (i+1) a # translate (r2 (-w,-2))
               <> tPic (i+1) b # translate (r2 (w,-1.8))
               <> fromVertices [p2 (-w, -2), p2 (0,0), p2 (w,-1.8)]
  where w = 3 * 0.7 ^ i

justLens :: a -> Lens' (Maybe a) a
justLens a = lens (maybe a id) (flip $ const . Just)

counter :: forall a . (Ord a) => a -> SubState (a, a) -> Create (SubStateEq a)
counter x ab = do
    c <- extendStateWith ab (fix . _2) (x, (x, x))
    pure $ fix . _1 `lensMap` withEq c
  where
    fix :: Lens' (a, (a,a)) (a, (a,a))
    fix = lens id $ \_ (x, ab@(a, b)) -> (min b $ max a x, ab)

interval :: (RefClass r, Ord a) => RefSimple r (a, a) -> (RefSimple r a, RefSimple r a)
interval ab = (lens fst set1 `lensMap` ab, lens snd set2 `lensMap` ab) where
    set1 (_, b) a = (min b a, b)
    set2 (a, _) b = (a, max a b)


----------------------------------------------------------------------------

inCanvasExample = do
    t <- extendState $ iterate (Node Leaf) Leaf !! 5
    i <- extendState (0 :: Int)
    j <- extendState 0
    s <- extendState "x"
    s' <- extendState "y"
    let x = vcat
            [ hcat
                [ vcat
                    [ hcat
                        [ label $ fmap (\i -> show i ++ "hello") $ value i
                        , primButton (pure "+1") (pure True) Nothing $ adjust i (+1)
                        ]
                    , hcat
                        [ entry s
                        , entry s
                        ]
                    , hcat
                        [ entry s'
                        , entry s'
                        ]
                    ]
                , combobox ["Hello","World","!"] j
                ]
            , tEditor3 t
            ]

    hcat [ inCanvas 200 300 15 $ vcat [x, inCanvas 100 100 15 x], x]



