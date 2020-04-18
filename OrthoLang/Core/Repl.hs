{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- TODO no welcome if going to load a file + clear the screen anyway

-- TODO could simplify to the same code everywhere except you pass the handle (file vs stdout)?

-- Based on:
-- http://dev.stephendiehl.com/hask/ (the Haskeline section)
-- https://github.com/goldfirere/glambda

-- TODO prompt to remove any bindings dependent on one the user is changing
--      hey! just store a list of vars referenced as you go too. much easier!
--      will still have to do that recursively.. don't try until after lab meeting

-- TODO you should be able to write comments in the REPL
-- TODO why doesn't prettyShow work anymore? what changed??
-- TODO should be able to :reload the current script, if any

module OrthoLang.Core.Repl
  -- ( mkRepl
  -- , runRepl
  -- )
  where

import qualified Data.Map.Strict as M
import System.Console.Haskeline hiding (catch)

import Control.Monad            (when)
import Control.Monad.IO.Class   (liftIO, MonadIO)
import Control.Monad.State.Lazy (get, put)
import Data.Char                (isSpace)
import Data.List                (isPrefixOf, isSuffixOf, filter, delete)
import Data.List.Utils          (delFromAL)
import Prelude           hiding (print)
import OrthoLang.Core.Help      (help, renderTypeSig)
import OrthoLang.Core.Eval       (evalScript)
import OrthoLang.Core.Parse      (isExpr, parseExpr, parseStatement, parseFile)
import OrthoLang.Core.Types
import OrthoLang.Core.Pretty     (pPrint, render, pPrintHdl, writeScript)
import OrthoLang.Util       (absolutize, stripWhiteSpace, justOrDie, headOrDie)
import OrthoLang.Core.Config     (showConfigField, setConfigField)
import System.Process           (runCommand, waitForProcess)
import System.IO                (Handle, hPutStrLn, stdout)
import System.Directory         (doesFileExist)
import System.FilePath.Posix    ((</>))
import Control.Exception.Safe   (Typeable, throw, try)
import System.Console.ANSI      (clearScreen, cursorUp)
import Data.IORef               (readIORef)
import Development.Shake.FilePath (takeFileName)
import Control.Monad.Trans.Maybe      (MaybeT(..), runMaybeT)
import Control.Monad.State.Strict (StateT, execStateT, evalStateT, lift)

-----------------
-- Repl monad --
----------------

type ReplM a = StateT GlobalEnv (MaybeT (InputT IO)) a
type IOEnv = StateT GlobalEnv IO
type ReplM2 = InputT IOEnv

-- TODO use useFile(Handle) for stdin?
-- TODO use getExternalPrint to safely print during Tasty tests!
runReplM :: Settings IO -> ReplM a -> GlobalEnv -> IO (Maybe GlobalEnv)
runReplM settings replm state =
  runInputT settings $ runMaybeT $ execStateT replm state

myComplete2 = undefined

replSettings2 :: Config -> Settings ReplM2
replSettings2 cfg = Settings
  { complete       = myComplete2
  , historyFile    = Just $ cfgTmpDir cfg </> "history.txt"
  , autoAddHistory = True
  }

runReplM2 :: Settings IOEnv -> InputT IOEnv a -> GlobalEnv -> IO a
runReplM2 mySettings replm state = evalStateT (runInputT mySettings replm) state

prompt :: String -> ReplM (Maybe String)
prompt = lift . lift . getInputLine

-------------------
-- main interface --
--------------------

clear :: IO ()
clear = clearScreen >> cursorUp 1000

runRepl :: Config -> LocksRef -> IDsRef -> DigestsRef -> IO ()
runRepl = mkRepl (repeat prompt) stdout

-- Like runRepl, but allows overriding the prompt function for golden testing.
-- Used by mockRepl in OrthoLang/Core/Repl/Tests.hs
mkRepl :: [(String -> ReplM (Maybe String))] -> Handle
       -> Config -> LocksRef -> IDsRef -> DigestsRef -> IO ()
mkRepl promptFns hdl cfg ref ids dRef = do
  -- load initial script if any
  st <- case cfgScript cfg of
          Nothing -> do
            clear
            hPutStrLn hdl
              "Welcome to the OrthoLang interpreter!\n\
              \Type :help for a list of the available commands."
            return  (emptyScript, cfg, ref, ids, dRef)
          Just path -> cmdLoad (emptyScript, cfg, ref, ids, dRef) hdl path
  -- run repl with initial state
  _ <- runReplM (replSettings st) (loop promptFns hdl) st
  return ()

-- promptArrow = " --‣ "
-- promptArrow = " ❱❱❱ "
-- promptArrow = " --❱ "
-- promptArrow = " ⋺  "
-- promptArrow = " >> "
-- promptArrow = "-> "
promptArrow :: String
promptArrow = " —▶ "

shortPrompt :: Config -> String
shortPrompt cfg = "\n" ++ name ++ promptArrow -- TODO no newline if last command didn't print anything
  where
    name = case cfgScript cfg of
      Nothing -> "ortholang"
      Just s  -> takeFileName s

-- There are four types of input we might get, in the order checked for:
-- TODO update this to reflect 3/4 merged
--   1. a blank line, in which case we just loop again
--   2. a REPL command, which starts with `:`
--   3. an assignment statement (even an invalid one)
--   4. a one-off expression to be evaluated
--      (this includes if it's the name of an existing var)
--
-- TODO if you type an existing variable name, should it evaluate the script
--      *only up to the point of that variable*? or will that not be needed
--      in practice once the kinks are worked out?
--
-- TODO improve error messages by only parsing up until the varname asked for!
-- TODO should the new statement go where the old one was, or at the end??
--
-- The weird list of prompt functions allows mocking stdin for golded testing.
-- (No need to mock print because stdout can be captured directly)
--
-- TODO replace list of prompts with pipe-style read/write from here?
--      http://stackoverflow.com/a/14027387
loop :: [(String -> ReplM (Maybe String))] -> Handle -> ReplM ()
-- loop [] hdl = get >>= \st -> liftIO (runCmd st hdl "quit") >> return ()
loop [] _ = return ()
loop (promptFn:promptFns) hdl = do
  st@(_, cfg, _, _, _)  <- get
  Just line <- promptFn $ shortPrompt cfg -- TODO can this fail?
  st' <- liftIO $ try $ step st hdl line
  case st' of
    Right s -> put s >> loop promptFns hdl
    Left (SomeException e) -> do
      liftIO $ hPutStrLn hdl $ show e
      return () -- TODO *only* return if it's QuitRepl; ignore otherwise

-- handler :: Handle -> SomeException -> IO (Maybe a)
-- handler hdl e = hPutStrLn hdl ("error! " ++ show e) >> return Nothing

-- TODO move to Types.hs
-- TODO use this pattern for other errors? or remove?

data QuitRepl = QuitRepl
  deriving Typeable

instance Exception QuitRepl

instance Show QuitRepl where
  show QuitRepl = "Bye for now!"

-- Attempts to process a line of input, but prints an error and falls back to
-- the current state if anything goes wrong. This should eventually be the only
-- place exceptions are caught.
step :: GlobalEnv -> Handle -> String -> IO GlobalEnv
step st hdl line = case stripWhiteSpace line of
  ""        -> return st
  ('#':_  ) -> return st
  (':':cmd) -> runCmd st hdl cmd
  statement -> runStatement st hdl statement

-- TODO insert ids
runStatement :: GlobalEnv -> Handle -> String -> IO GlobalEnv
runStatement st@(scr, cfg, ref, ids, dRef) hdl line = case parseStatement (cfg, scr) line of
  Left  e -> hPutStrLn hdl e >> return st
  Right r -> do
    let st' = (updateVars scr r, cfg, ref, ids, dRef)
    when (isExpr (cfg, scr) line) (evalScript hdl st')
    return st'

-- this is needed to avoid assigning a variable literally to itself,
-- which is especially a problem when auto-assigning "result"
-- TODO is this where we can easily require the replacement var's type to match if it has deps?
-- TODO what happens if you try that in a script? it should fail i guess?
updateVars :: Script -> Assign -> Script
updateVars scr asn@(var, _) = as'
  where
    res = Var (RepID Nothing) "result"
    asn' = removeSelfReferences scr asn
    as' = if var /= res && var `elem` map fst scr
            then replaceVar asn' scr
            else delFromAL scr var ++ [asn']

-- replace an existing var in a script
replaceVar :: Assign -> [Assign] -> [Assign]
replaceVar a1@(v1, _) = map $ \a2@(v2, _) -> if v1 == v2 then a1 else a2

-- makes it ok to assign a var to itself in the repl
-- by replacing the reference with its value at that point
-- TODO forbid this in scripts though
removeSelfReferences :: Script -> Assign -> Assign
removeSelfReferences s a@(v, e) = if not (v `elem` depsOf e) then a else (v, dereference s v e)

-- does the actual work of removing self-references
dereference :: Script -> Var -> Expr -> Expr
dereference scr var e@(Ref _ _ _ v2)
  | var == v2 = justOrDie "failed to dereference variable!" $ lookup var scr
  | otherwise = e
dereference _   _   e@(Lit _ _) = e
dereference _   _   (Com _) = error "implement this! or rethink?"
dereference scr var (Bop  t ms vs s e1 e2) = Bop  t ms (delete var vs) s (dereference scr var e1) (dereference scr var e2)
dereference scr var (Fun  t ms vs s es   ) = Fun  t ms (delete var vs) s (map (dereference scr var) es)
dereference scr var (Lst t vs   es   ) = Lst t (delete var vs)   (map (dereference scr var) es)

--------------------------
-- dispatch to commands --
--------------------------

runCmd :: GlobalEnv -> Handle -> String -> IO GlobalEnv
runCmd st@(_, cfg, _, _, _) hdl line = case matches of
  [(_, fn)] -> fn st hdl $ stripWhiteSpace args
  []        -> hPutStrLn hdl ("unknown command: "   ++ cmd) >> return st
  _         -> hPutStrLn hdl ("ambiguous command: " ++ cmd) >> return st
  where
    (cmd, args) = break isSpace line
    matches = filter ((isPrefixOf cmd) . fst) (cmds cfg)

cmds :: Config -> [(String, GlobalEnv -> Handle -> String -> IO GlobalEnv)]
cmds cfg =
  [ ("help"     , cmdHelp    )
  , ("load"     , cmdLoad    )
  , ("write"    , cmdWrite   ) -- TODO do more people expect 'save' or 'write'?
  , ("needs"    , cmdNeeds   )
  , ("neededfor", cmdNeededBy)
  , ("drop"     , cmdDrop    )
  , ("type"     , cmdType    )
  , ("show"     , cmdShow    )
  , ("reload"   , cmdReload  )
  , ("quit"     , cmdQuit    )
  , ("config"   , cmdConfig  )
  ]
  ++ if cfgSecure cfg then [] else [("!", cmdBang)]

---------------------------
-- run specific commands --
---------------------------

-- TODO load this from a file?
-- TODO update to include :config getting + setting
-- TODO if possible, make this open in `less`?
-- TODO why does this one have a weird path before the :help text?
-- TODO bop help by mapping to the prefixOf version
cmdHelp :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdHelp st@(_, cfg, _, _, _) hdl line = do
  doc <- help cfg line
  hPutStrLn hdl doc >> return st

-- TODO this is totally duplicating code from putAssign; factor out
-- TODO should it be an error for the new script not to play well with an existing one?
cmdLoad :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdLoad st@(scr, cfg, ref, ids, dRef) hdl path = do
  clear
  path' <- absolutize path
  dfe   <- doesFileExist path'
  if not dfe
    then hPutStrLn hdl ("no such file: " ++ path') >> return st
    else do
      let cfg' = cfg { cfgScript = Just path' } -- TODO why the False??
      new <- parseFile (scr, cfg', ref, ids, dRef) path' -- TODO insert ids
      case new of
        Left  e -> hPutStrLn hdl (show e) >> return st
        -- TODO put this back? not sure if it makes repl better
        Right s -> cmdShow (s, cfg', ref, ids, dRef) hdl ""
        -- Right s -> return (s, cfg', ref, ids, dRef)

cmdReload :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdReload st@(_, cfg, _, _, _) hdl _ = case cfgScript cfg of
  Nothing -> cmdDrop st hdl ""
  Just s  -> cmdLoad st hdl s

cmdWrite :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdWrite st@(scr, cfg, locks, ids, dRef) hdl line = case words line of
  [path] -> do
    saveScript cfg scr path
    return (scr, cfg { cfgScript = Just path }, locks, ids, dRef)
  [var, path] -> case lookup (Var (RepID Nothing) var) scr of
    Nothing -> hPutStrLn hdl ("Var \"" ++ var ++ "' not found") >> return st
    Just e  -> saveScript cfg (depsOnly e scr) path >> return st
  _ -> hPutStrLn hdl ("invalid save command: \"" ++ line ++ "\"") >> return st

-- TODO where should this go?
depsOnly :: Expr -> Script -> Script
depsOnly expr scr = deps ++ [res]
  where
    deps = filter (\(v,_) -> (elem v $ depsOf expr)) scr
    res  = (Var (RepID Nothing) "result", expr)

-- TODO where should this go?
saveScript :: Config -> Script -> FilePath -> IO ()
saveScript cfg scr path = absolutize path >>= \p -> writeScript cfg scr p

-- TODO factor out the variable lookup stuff
-- TODO except, this should work with expressions too!
cmdNeededBy :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdNeededBy st@(scr, cfg, _, _, _) hdl var = do
  case lookup (Var (RepID Nothing) var) scr of
    Nothing -> hPutStrLn hdl $ "Var \"" ++ var ++ "' not found"
    -- Just e  -> prettyAssigns hdl (\(v,_) -> elem v $ (Var Nothing var):depsOf e) scr
    Just e  -> pPrintHdl cfg hdl $ filter (\(v,_) -> elem v $ (Var (RepID Nothing) var):depsOf e) scr
  return st

-- TODO move to Pretty.hs
-- prettyAssigns :: Handle -> (Assign -> Bool) -> Script -> IO ()
-- prettyAssigns hdl fn scr = do
  -- txt <- renderIO $ pPrint $ filter fn scr
  -- hPutStrLn hdl txt

cmdNeeds :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdNeeds st@(scr, cfg, _, _, _) hdl var = do
  let var' = Var (RepID Nothing) var
  case lookup var' scr of
    Nothing -> hPutStrLn hdl $ "Var \"" ++ var ++ "' not found"
    Just _  -> pPrintHdl cfg hdl $ filter (\(v,_) -> elem v $ (Var (RepID Nothing) var):rDepsOf scr var') scr
  return st

-- TODO factor out the variable lookup stuff
cmdDrop :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdDrop (_, cfg, ref, ids, dRef) _ [] = clear >> return (emptyScript, cfg { cfgScript = Nothing }, ref, ids, dRef) -- TODO drop ids too?
cmdDrop st@(scr, cfg, ref, ids, dRef) hdl var = do
  let v = Var (RepID Nothing) var
  case lookup v scr of
    Nothing -> hPutStrLn hdl ("Var \"" ++ var ++ "' not found") >> return st
    Just _  -> return (delFromAL scr v, cfg, ref, ids, dRef)

cmdType :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdType st@(scr, cfg, _, _, _) hdl s = hPutStrLn hdl typeInfo >> return st
  where
    typeInfo = case stripWhiteSpace s of
      "" -> allTypes
      s' -> oneType s'
    oneType e = case findFunction cfg e of
      Just f  -> renderTypeSig f
      Nothing -> showExprType st e -- TODO also show the expr itself?
    allTypes = init $ unlines $ map showAssignType scr

-- TODO insert id?
showExprType :: GlobalEnv -> String -> String
showExprType (s, c, _, _, _) e = case parseExpr (c, s) e of
  Right expr -> show $ typeOf expr
  Left  err  -> show err

showAssignType :: Assign -> String
showAssignType (Var _ v, e) = unwords [typedVar, "=", prettyExpr]
  where
    -- parentheses also work:
    -- typedVar = v ++ " (" ++ show (typeOf e) ++ ")"
    typedVar = v ++ "." ++ show (typeOf e)
    prettyExpr = render $ pPrint e

-- TODO factor out the variable lookup stuff
-- TODO show the whole script, since that only shows sAssigns now anyway?
cmdShow :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdShow st@(s, c, _, _, _) hdl [] = mapM_ (pPrintHdl c hdl) s >> return st
cmdShow st@(scr, cfg, _, _, _) hdl var = do
  case lookup (Var (RepID Nothing) var) scr of
    Nothing -> hPutStrLn hdl $ "Var \"" ++ var ++ "' not found"
    Just e  -> pPrintHdl cfg hdl e
  return st

-- TODO does this one need to be a special case now?
cmdQuit :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdQuit _ _ _ = throw QuitRepl
-- cmdQuit _ _ _ = ioError $ userError "Bye for now!"

cmdBang :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdBang st _ cmd = (runCommand cmd >>= waitForProcess) >> return st

-- TODO if no args, dump whole config by pretty-printing
-- TODO wow much staircase get rid of it
cmdConfig :: GlobalEnv -> Handle -> String -> IO GlobalEnv
cmdConfig st@(scr, cfg, ref, ids, dRef) hdl s = do
  let ws = words s
  if (length ws == 0)
    then pPrintHdl cfg hdl cfg >> return st -- TODO Pretty instance
    else if (length ws  > 2)
      then hPutStrLn hdl "too many variables" >> return st
      else if (length ws == 1)
        then hPutStrLn hdl (showConfigField cfg $ headOrDie "cmdConfig failed" ws) >> return st
        else case setConfigField cfg (headOrDie "cmdConfig failed" ws) (last ws) of
               Left err -> hPutStrLn hdl err >> return st
               Right iocfg' -> do
                 cfg' <- iocfg'
                 return (scr, cfg', ref, ids, dRef)

--------------------
-- tab completion --
--------------------

-- complete things in quotes: filenames, seqids
quotedCompletions :: MonadIO m => GlobalEnv -> String -> m [Completion]
quotedCompletions (_, _, _, idRef, _) wordSoFar = do
  files  <- listFiles wordSoFar
  seqIDs <- fmap (map $ headOrDie "quotedCompletions failed" . words) $ fmap M.elems $ fmap (M.unions . M.elems . hSeqIDs) $ liftIO $ readIORef idRef
  let seqIDs' = map simpleCompletion $ filter (wordSoFar `isPrefixOf`) seqIDs
  return $ files ++ seqIDs'

-- complete everything else: fn names, var names, :commands, types
-- these can be filenames too, but only if the line starts with a :command
nakedCompletions :: MonadIO m => GlobalEnv -> String -> String -> m [Completion]
nakedCompletions (scr, cfg, _, _, _) lineReveresed wordSoFar = do
  files <- if ":" `isSuffixOf` lineReveresed then listFiles wordSoFar else return []
  return $ files ++ (map simpleCompletion $ filter (wordSoFar `isPrefixOf`) wordSoFarList)
  where
    wordSoFarList = fnNames ++ varNames ++ cmdNames ++ typeExts
    fnNames  = concatMap (map fName . mFunctions) (cfgModules cfg)
    varNames = map ((\(Var _ v) -> v) . fst) scr
    cmdNames = map ((':':) . fst) (cmds cfg)
    typeExts = map tExtOf $ concatMap mTypes $ cfgModules cfg

-- this is mostly lifted from Haskeline's completeFile
myComplete :: MonadIO m => GlobalEnv -> CompletionFunc m
myComplete s = completeQuotedWord   (Just '\\') "\"\"" (quotedCompletions s)
             $ completeWordWithPrev (Just '\\') ("\"\'" ++ filenameWordBreakChars)
                                    (nakedCompletions s)

-- This is separate from the Config because it shouldn't need changing.
-- TODO do we actually need the script here? only if we're recreating it every loop i guess
replSettings :: GlobalEnv -> Settings IO
replSettings s@(_, cfg, _, _, _) = Settings
  { complete       = myComplete s
  , historyFile    = Just $ cfgTmpDir cfg </> "history.txt"
  , autoAddHistory = True
  }
