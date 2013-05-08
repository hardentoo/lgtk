module LGtk.Demos.Main
    ( main
    ) where

import Control.Monad
import Control.Monad.Trans
import Control.Concurrent
import Prelude hiding (id, (.))

import LGtk

import Control.Monad.Restricted
import LGtk.Demos.Tri
import LGtk.Demos.IntListEditor
import LGtk.Demos.TEditor

main :: IO ()
main = runWidget $ notebook
    [ (,) "Hello" $ Label $ constSend "Hello World!"

    , (,) "Counters" $ notebook

        [ (,) "Unbounded" $ Action $ do
            c <- newRef 0
            return $ vcat
                [ Label $ rEffect $ liftM show $ readRef c
                , hcat
                    [ smartButton (constSend "+1") (return . (+1)) c
                    , smartButton (constSend "-1") (return . (+(-1))) c
                    ]
                ]

        , (,) "1..3" $ Action $ do
            c <- newRef 1
            return $ vcat
                [ Label $ rEffect $ liftM show $ readRef c
                , hcat
                    [ smartButton (constSend "+1") (return . min 3 . (+1)) c
                    , smartButton (constSend "-1") (return . max 1 . (+(-1))) c
                    ]
                ]

        , (,) "a..b" $ Action $ do
            a <- newRef 1
            b <- newRef 3
            let a' = joinRef $ do
                    bv <- readRef b
                    return $ lens id (const . min bv) % a
            let b' = joinRef $ do
                    av <- readRef a
                    return $ lens id (const . max av) % b
            return $ vcat
                [ counter a' b'
                , hcat [ Label $ constSend "min", entry $ showLens % a' ]
                , hcat [ Label $ constSend "max", entry $ showLens % b' ]
                ]

        ]

    , (,) "TabSwitch" $ Action $ do
        x <- newRef "a"
        let w = vcat [ Label $ rEffect $ readRef x, entry x ]
        return $ notebook
            [ (,) "T1" w
            , (,) "T2" w
            ]

    , (,) "Async" $ Action $ do
        ready <- newRef True
        delay <- newRef 1.0
        unsafeC $ do
            v <- liftEffectM $ liftIO newEmptyMVar
            toReceive (writeRef ready) $ \re -> liftIO $ void $ forkIO $ forever $ do
                _ <- takeMVar v
                re True
                return ()
            rEffect (liftM2 (,) (readRef ready) (readRef delay)) $ \(b, d) -> when (not b) $ do
                liftIO $ forkIO $ do
                    threadDelay $ ceiling $ 10^6 * d
                    putMVar v ()
                return ()
        return $ vcat
            [ entry $ showLens % delay
            , Button (constSend "Start long computation") (rEffect $ readRef ready) $ toReceive $ const $ writeRef ready False
            , Label $ rEffect $ liftM (\b -> if b then "Ready." else "Computing...") $ readRef ready
            ]

    , (,) "IntListEditor" $ Action $ do
        state <- fileRef "intListEditorState.txt"
        settings <- fileRef "intListEditorSettings.txt"
        return $ intListEditor (justLens "" % state) (justLens "" % settings)
    , (,) "Tri" tri
    , (,) "T-Editor1" tEditor1
    , (,) "T-Editor3" $ Action $ newRef (iterate (Node Leaf) Leaf !! 10) >>= tEditor3
    ]

justLens :: a -> Lens (Maybe a) a
justLens a = lens (maybe a id) (const . Just)

counter a b = Action $ do
    c <- newRef 0
    let c' = joinRef $ do
            av <- readRef a
            bv <- readRef b
            return $ iso (min bv . max av) id % c
    return $ vcat
        [ Label $ rEffect $ liftM show $ readRef c'
        , hcat
            [ smartButton (constSend "+1") ((\x -> liftM (min x) $ readRef b) . (+1)) c'
            , smartButton (constSend "-1") ((\x -> liftM (max x) $ readRef a) . (+(-1))) c'
            ]
        ]

