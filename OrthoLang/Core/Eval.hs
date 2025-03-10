{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecordWildCards #-}

{- OrthoLang code is interpreted in phases, but client code shouldn't need to
 - care about that, so this module wraps them in a simplified interface. It
 - just holds whatever [i]nterpret functions the Repl and OrthoLang modules use
 - for now rather than any comprehensive API.
 -}

-- TODO ghc --make MyBuildSystem -rtsopts -with-rtsopts=-I0
-- TODO -j (is that done already?)
-- TODO --flush=N

-- TODO should there be an iLine function that tries both expr and assign?
-- TODO create Eval.hs again and move [e]val functions there? might be clearer
--      but then again interpret and eval are kind of the same thing here right?
--      it's either interpret or compile + eval

module OrthoLang.Core.Eval
  ( eval
  , evalFile
  , evalScript
  )
  where

import Development.Shake
import Text.PrettyPrint.HughesPJClass hiding ((<>))

import OrthoLang.Core.Types
import OrthoLang.Core.Pretty (renderIO)
-- import OrthoLang.Core.Config (debug)

-- import Control.Applicative ((<>))
-- import qualified Data.Map as M
-- import Data.List (isPrefixOf)

import Data.Maybe                     (maybeToList, isJust, fromMaybe, fromJust)
import OrthoLang.Core.Compile.Basic    (compileScript, rExpr)
import OrthoLang.Core.Parse            (parseFileIO)
import OrthoLang.Core.Pretty           (prettyNum)
import OrthoLang.Core.Paths            (OrthoLangPath, toOrthoLangPath, fromOrthoLangPath)
import OrthoLang.Core.Locks            (withReadLock')
import OrthoLang.Core.Sanitize         (unhashIDs, unhashIDsFile)
import OrthoLang.Core.Actions          (readLits, readPaths)
import OrthoLang.Core.Util             (trace)
import System.IO                      (Handle)
import System.FilePath                ((</>), takeFileName)
import Data.IORef                     (readIORef)
import Control.Monad                  (when)
import GHC.Conc (numCapabilities)
-- import System.Directory               (createDirectoryIfMissing)
-- import Control.Concurrent.Thread.Delay (delay)
import Control.Retry          (rsIterNumber)
import Control.Exception.Safe (catchAny)

import Control.Concurrent
-- import Data.Foldable
import qualified System.Progress as P
-- import Data.IORef
-- import Data.Monoid
-- import Control.Monad

import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import System.Time.Utils (renderSecs)

-- TODO what's an optimal number?
numInterpreterThreads :: Int
numInterpreterThreads = max 1 $ numCapabilities - 1

-- TODO how to update one last time at the end?
-- sample is in milliseconds (1000 = a second)
updateLoop :: Int -> IO a -> IO b
updateLoop delay updateFn = do
  threadDelay delay
  _ <- updateFn
  updateLoop delay updateFn

updateProgress :: P.Meter' EvalProgress -> IO Progress -> IO ()
updateProgress pm iosp = do
  -- putStrLn "updating progress"
  Progress{..} <- iosp -- this is weird, but the types check!
  let d = countBuilt + countSkipped + 1
      t = countBuilt + countSkipped + countTodo
  update <- getCurrentTime
  P.modifyMeter pm (\ep -> ep {epDone = d, epTotal = t, epUpdate = update})
  -- unless (d >= t) $ do
    -- threadDelay $ 1000 * 100
    -- updateProgress pm iosp
  -- return ()

completeProgress :: P.Meter' EvalProgress -> Action ()
completeProgress pm = do
  liftIO $ P.modifyMeter pm (\ep2 -> ep2 {epDone = epTotal ep2})
  Exit _ <- command [] "sync" [] -- why is this needed?
  return ()

data EvalProgress = EvalProgress
  { epTitle   :: String

  -- together these two let you get duration,
  -- and epUpdate alone seeds the progress bar animation (if any)
  , epUpdate  :: UTCTime
  , epStart   :: UTCTime

  , epDone    :: Int
  , epTotal   :: Int
  , epThreads :: Int
  , epWidth   :: Int
  , epArrowHead :: Char
  , epArrowShaft :: Char
  }

-- TODO hey should the state just be a Progress{..} itself? seems simpler + more flexible
renderProgress :: EvalProgress -> String
renderProgress EvalProgress{..}
  | (round $ diffUTCTime epUpdate epStart) < 5 || epDone == 0 = ""
  | otherwise = unwords $ [epTitle, "[" ++ arrow ++ "]"] ++ [fraction, time]
  where
    -- details  = if epDone >= epTotal then [] else [fraction]
    time = renderTime epStart epUpdate
    fraction = "[" ++ working ++ "/" ++ show epTotal ++ "]" -- TODO skip fraction when done
    firstTask = min epTotal $ epDone + 1
    lastTask  = min epTotal $ epDone + epThreads
    threads  = if firstTask == lastTask then 1 else lastTask - firstTask + 1
    working  = show firstTask ++ if threads < 2 then "" else "-" ++ show lastTask
    arrowWidth = epWidth - length epTitle - length time - length fraction
    arrowFrac  = ((fromIntegral epDone) :: Double) / (fromIntegral epTotal)
    arrow = if epStart == epUpdate then replicate arrowWidth ' '
            else renderBar arrowWidth threads arrowFrac epArrowShaft epArrowHead

renderTime :: UTCTime -> UTCTime -> String
renderTime start update = renderSecs $ round $ diffUTCTime update start

renderBar :: Int -> Int -> Double -> Char -> Char -> String
renderBar total _ fraction _ _ | fraction == 0 = replicate total ' '
renderBar total nThreads fraction shaftChar headChar = shaft ++ heads ++ blank
  where
    -- hl a = map (\(i, c) -> if (updates + i) `mod` 15 == 0 then '-' else c) $ zip [1..] a
    len     = ceiling $ fraction * fromIntegral total
    shaft   = replicate len shaftChar
    heads   = replicate nThreads headChar
    blank   = replicate (total - len - nThreads - 1) ' '

-- TODO use hashes + dates to decide which files to regenerate?
-- alternatives tells Shake to drop duplicate rules instead of throwing an error
myShake :: OrthoLangConfig -> P.Meter' EvalProgress -> Int -> Rules () -> IO ()
myShake cfg pm delay rules = do
  -- ref <- newIORef (return mempty :: IO Progress)
  let shakeOpts = shakeOptions
        { shakeFiles     = cfgTmpDir cfg
        -- , shakeVerbosity = if isJust (cfgDebug cfg) then Chatty else Quiet
        , shakeVerbosity = Quiet
        , shakeThreads   = numInterpreterThreads
        , shakeReport    = [cfgTmpDir cfg </> "profile.html"] ++ maybeToList (cfgReport cfg)
        , shakeAbbreviations = [(cfgTmpDir cfg, "$TMPDIR"), (cfgWorkDir cfg, "$WORKDIR")]
        , shakeChange    = ChangeModtimeAndDigest -- TODO test this
        -- , shakeCommandOptions = [EchoStdout True]
        , shakeProgress = updateLoop delay . updateProgress pm
        -- , shakeShare = cfgShare cfg -- TODO why doesn't this work?
        -- , shakeCloud = ["localhost"] -- TODO why doesn't this work?
        -- , shakeLineBuffering = True
        -- , shakeStaunch = True -- TODO is this a good idea?
        -- , shakeColor = True
        -- TODO shakeShare to implement shared cache on the demo site!
        }

  (shake shakeOpts . alternatives) rules
  -- removeIfExists $ cfgTmpDir cfg </> ".shake.lock"
  --
{- This seems to be separately required to show the final result of eval.
 - It can't be moved to Pretty.hs either because that causes an import cycle.
 -
 - TODO is there a way to get rid of it?
 - TODO rename prettyContents? prettyResult?
 - TODO should this actually open external programs
 - TODO idea for sets: if any element contains "\n", just add blank lines between them
 - TODO clean this up!
 -}
prettyResult :: OrthoLangConfig -> Locks -> OrthoLangType -> OrthoLangPath -> Action Doc
prettyResult _ _ Empty  _ = return $ text "[]"
prettyResult cfg ref (ListOf t) f
  | t `elem` [str, num] = do
    lits <- readLits cfg ref $ fromOrthoLangPath cfg f
    let lits' = if t == str
                  then map (\s -> text $ "\"" ++ s ++ "\"") lits
                  else map prettyNum lits
    return $ text "[" <> sep ((punctuate (text ",") lits')) <> text "]"
  | otherwise = do
    paths <- readPaths cfg ref $ fromOrthoLangPath cfg f
    pretties <- mapM (prettyResult cfg ref t) paths
    return $ text "[" <> sep ((punctuate (text ",") pretties)) <> text "]"
prettyResult cfg ref (ScoresOf _)  f = do
  s <- liftIO (defaultShow cfg ref $ fromOrthoLangPath cfg f)
  return $ text s
prettyResult cfg ref t f = liftIO $ fmap showFn $ (tShow t cfg ref) f'
  where
    showFn = if t == num then prettyNum else text
    f' = fromOrthoLangPath cfg f

-- run the result of any of the c* functions, and print it
-- (only compileScript is actually useful outside testing though)
-- TODO rename `runRules` or `runShake`?
-- TODO require a return type just for showing the result?
-- TODO take a variable instead?
-- TODO add a top-level retry here? seems like it would solve the read issues
eval :: Handle -> OrthoLangConfig -> Locks -> HashedIDsRef -> OrthoLangType -> Rules [ExprPath] -> Rules ResPath -> IO ()
eval hdl cfg ref ids rtype ls p = do
  start <- getCurrentTime
  let ep = EvalProgress
             { epTitle = takeFileName $ fromMaybe "ortholang" $ cfgScript cfg
             , epStart  = start
             , epUpdate = start
             , epDone    = 0
             , epTotal   = 0
             , epThreads = numInterpreterThreads
             , epWidth = fromMaybe 80 $ cfgWidth cfg
             , epArrowShaft = '—'
             , epArrowHead = '▶'
             }
      delay = 1000000 -- in microseconds
      pOpts = P.Progress
                { progressDelay = delay
                , progressHandle = hdl
                , progressInitial = ep
                , progressRender = if cfgNoProg cfg then (const "") else renderProgress
                }
  if isJust (cfgDebug cfg)
    then ignoreErrors $ eval' delay pOpts ls p
    else ignoreErrors $ eval' delay pOpts ls p -- TODO retry again for production?
  where
    -- ignoreErrors fn = catchAny fn (\_ -> return ())
    ignoreErrors fn = catchAny fn (\e -> putStrLn ("ignored error: " ++ show e))
    -- Reports how many failures so far and runs the main fn normally
    -- TODO putStrLn rather than debug?
    -- TODO remove if not using retryIgnore?
    report fn status = case rsIterNumber status of
      0 -> fn
      n -> trace "core.eval.eval" ("error! eval failed " ++ show n ++ " times") fn

    eval' delay pOpts lpaths rpath = P.withProgress pOpts $ \pm -> myShake cfg pm delay $ do
      lpaths' <- (fmap . map) (\(ExprPath p) -> p) lpaths
      (ResPath path) <- rpath
      want ["eval"]
      "eval" ~> do
        alwaysRerun
        actionRetry 9 $ need $ lpaths' ++ [path] -- TODO is this done automatically in the case of result?
        {- if --interactive, print the short version of a result
         - if --output, save the full result (may also be --interactive)
         - if neither, print the full result
         - TODO move this logic to the top level?
         -}
        -- ids' <- liftIO $ readIORef ids
        when (cfgInteractive cfg) (printShort cfg ref ids pm rtype path)
        completeProgress pm
        case cfgOutFile cfg of
          Just out -> writeResult cfg ref ids (toOrthoLangPath cfg path) out
          Nothing  -> when (not $ cfgInteractive cfg) (printLong cfg ref ids pm path)
        return ()

writeResult :: OrthoLangConfig -> Locks -> HashedIDsRef -> OrthoLangPath -> FilePath -> Action ()
writeResult cfg ref idsref path out = do
  -- liftIO $ putStrLn $ "writing result to '" ++ out ++ "'"
  unhashIDsFile cfg ref idsref path out

-- TODO what happens when the txt is a binary plot image?
printLong :: OrthoLangConfig -> Locks -> HashedIDsRef -> P.Meter' EvalProgress -> FilePath -> Action ()
printLong _ ref idsref pm path = do
  ids <- liftIO $ readIORef idsref
  txt <- withReadLock' ref path $ readFile' path
  let txt' = unhashIDs False ids txt
  liftIO $ P.putMsgLn pm ("\n" ++ txt')

printShort :: OrthoLangConfig -> Locks -> HashedIDsRef -> P.Meter' EvalProgress -> OrthoLangType -> FilePath -> Action ()
printShort cfg ref idsref pm rtype path = do
  ids <- liftIO $ readIORef idsref
  res  <- prettyResult cfg ref rtype $ toOrthoLangPath cfg path
  -- liftIO $ putStrLn $ show ids
  -- liftIO $ putStrLn $ "rendering with unhashIDs (" ++ show (length $ M.keys ids) ++ " keys)..."
  -- TODO fix the bug that causes this to remove newlines after seqids:
  res' <- fmap (unhashIDs False ids) $ liftIO $ renderIO cfg res -- TODO why doesn't this handle a str.list?
  liftIO $ P.putMsgLn pm res'
  -- liftIO $ putStrLn $ "done rendering with unhashIDs"

-- TODO get the type of result and pass to eval
evalScript :: Handle -> OrthoLangState -> IO ()
evalScript hdl s@(as, c, ref, ids) =
  let res = case lookupResult as of
              Nothing -> fromJust $ lookupResult $ ensureResult as
              Just r  -> r
      loadExprs = extractLoads as res
      loads = mapM (rExpr s) $ trace "ortholang.core.eval.evalScript" ("load expressions: " ++ show loadExprs) loadExprs
  in eval hdl c ref ids (typeOf res) loads (compileScript s $ ReplaceID Nothing)

evalFile :: Handle -> OrthoLangConfig -> Locks -> HashedIDsRef -> IO ()
evalFile hdl cfg ref ids = case cfgScript cfg of
  Nothing  -> putStrLn "no script during eval. that's not right!"
  Just scr -> do
    s <- parseFileIO cfg ref ids scr -- TODO just take a OrthoLangState?
    evalScript hdl (s, cfg, ref, ids)
