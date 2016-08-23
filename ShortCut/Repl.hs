{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- Based on:
-- http://dev.stephendiehl.com/hask/ (the Haskeline section)
-- https://github.com/goldfirere/glambda

-- TODO prompt to remove any bindings dependent on one the user is changing
--      hey! just store a list of vars referenced as you go too. much easier!
--      will still have to do that recursively.. don't try until after lab meeting

-- TODO you should be able to write comments in the REPL
-- TODO why doesn't prettyShow work anymore? what changed??

module ShortCut.Repl where

-- import Text.Parsec (ParseError) -- TODO re-export from Types.hs
import ShortCut.Types
import ShortCut.Interpret
import ShortCut.Utils                 (absolutize)
-- import Control.Monad.Except           (throwError, MonadError)
import Control.Monad.IO.Class         (liftIO)
import Control.Monad.Identity         (mzero)
-- import Control.Monad.RWS.Lazy         (get, put, ask)
-- import Control.Monad.Reader           (MonadReader)
-- import Control.Monad.State            (MonadState, get, put)
-- import Control.Monad.Writer           (MonadWriter)
import Data.Char                      (isSpace)
import Data.List                      (dropWhileEnd, isPrefixOf)
import Data.List.Utils                (delFromAL)
import Data.Maybe                     (fromJust, fromMaybe)
import Prelude                 hiding (print)
import System.Command                 (runCommand, waitForProcess)
-- import Control.Monad (when)
-- import Text.PrettyPrint.HughesPJClass (prettyShow)
-- import Control.Monad (when)
-- import Control.Monad.IO.Class         (MonadIO, liftIO)
-- import Control.Monad.Trans.Maybe      (MaybeT(..), runMaybeT)
-- import Control.Monad.Trans            (lift)
-- import System.Console.Haskeline       (InputT, runInputT, defaultSettings
import System.Console.Haskeline       (InputT, getInputLine)
-- import Control.Monad.Except   (MonadError, ExceptT, runExceptT)
-- import Control.Monad.IO.Class (MonadIO)
-- import Control.Monad.State    (MonadState, get, put)
-- import Control.Monad.Trans    (MonadTrans, lift)
import Control.Monad.Trans    (lift)
-- import Data.List              (intersperse)

----------------
-- Repl monad --
----------------

-- newtype Repl a = Repl { unRepl :: MaybeT (ParserT (InputT IO)) a }
--   deriving
--     ( Functor
--     , Applicative
--     , Monad
--     , MonadIO
--     -- , MonadState CutState
--     -- , MonadError ParseError
--     )

-- first we get input from the user -----------------
--                                                  |
-- if they quit, it's all for Nothing -------       |
--                                          |       |
-- otherwise, parse it --------------       |       |
--                                  |       |       |
--                                  v       v       v
-- newtype Repl a = Repl { unRepl :: ParserT (MaybeT (InputT IO)) a } 
-- newtype Repl a = Repl { unRepl :: ParserT (InputT IO) a } 

type Repl a = ParserT (InputT IO) a

-- type Repl a = MaybeT (ParserT (InputT IO)) a

-- TODO can you remove the MaybeT altogether by quitting immediately on ":quit"?
--      would get rid of the nice prefix ability they have now :(

-- steps to evaluating Repl a:
-- check if Nothing or Just (the rest)
-- if just, need to runParser with user input
-- then get back Either ParseError or an a

-- InputT brings lines of input from the user,
-- and MaybeT handles the Nothing resulting from quitting the Repl
-- type Repl a = MaybeT (ParserT (InputT IO)) a

-- runRepl :: Repl a -> CutState -> IO (Either CutError (Maybe a), CutState)
-- runRepl :: Repl a -> CutConfig -> IO (Either ParseError (Maybe a))
-- runRepl r c = runInputT defaultSettings $ runParserT ([], c) (runMaybeT $ unRepl r) c ()
-- runRepl r s = runInputT defaultSettings $ runParserT pAssign (runMaybeT r) s
-- runRepl r s = runParserT (runMaybeT $ unRepl r) s $ runInputT defaultSettings
-- runRepl = undefined -- TODO write this!
-- runRepl repl cfg = runParserT pAssign ([], cfg)
                     -- (runMaybeT (runInputT defaultSettings) repl)

runRepl = undefined

prompt :: String -> Repl (Maybe String)
prompt = lift . getInputLine

print :: String -> Repl ()
print = liftIO . putStrLn

---------------
-- utilities --
---------------

stripWhiteSpace :: String -> String
stripWhiteSpace = dropWhile isSpace . dropWhileEnd isSpace

--------------------
-- main interface --
--------------------

repl :: CutConfig -> IO ()
repl cfg = welcome >> runRepl loop ([], cfg) >> goodbye

welcome :: IO ()
welcome = putStrLn
  "Welcome to the ShortCut interpreter!\n\
  \Type :help for a list of the available commands."

goodbye :: IO ()
goodbye = putStrLn "Bye for now!"

-- There are four types of input we might get, in the order checked for:
--   1. a blank line, in which case we just loop again
--   2. a REPL command, which starts with `:`
--   3. an assignment statement (even an invalid one)
--   4. a one-off expression to be evaluated
--      (this includes if it's the name of an existing var)
--
-- TODO if you type an existing variable name, should it evaluate the script
--      *only up to the point of that variable*? or will that not be needed
--      in practice once the kinks are worked out?
-- TODO improve error messages by only parsing up until the varname asked for!
-- TODO should the new statement go where the old one was, or at the end??
loop :: Repl ()
loop = do
  mline <- prompt "shortcut >> "
  case stripWhiteSpace (fromJust mline) of -- can this ever be Nothing??
    "" -> return ()
    (':':cmd) -> runCmd cmd
    line -> do
      cfg <- getConfig
      scr <- getScript
      if isAssignment (scr, cfg) line
        then do
          case iAssign (scr, cfg) line of
            Left  e -> print $ show e
            Right a -> putAssign a
        else do
          -- TODO how to handle if the var isn't in the script??
          -- TODO hook the logs + configs together?
          -- TODO only evaluate up to the point where the expression they want?
          case iExpr (scr, cfg) line of
            -- Left  err -> throwError err
            Left  err  -> fail $ "oh no! " ++ show err
            Right expr -> do
              let res  = CutVar "result"
                  scr' = delFromAL scr res ++ [(res,expr)]
              liftIO $ eval $ cScript res scr'
  loop

--------------------------
-- dispatch to commands --
--------------------------

runCmd :: String -> Repl ()
runCmd line = case matches of
  [(_, fn)] -> fn $ stripWhiteSpace args
  []        -> print $ "unknown command: "   ++ cmd
  _         -> print $ "ambiguous command: " ++ cmd
  where
    (cmd, args) = break isSpace line
    matches = filter ((isPrefixOf cmd) . fst) cmds

cmds :: [(String, String -> Repl ())]
cmds =
  [ ("help" , cmdHelp)
  , ("load" , cmdLoad)
  , ("write", cmdSave)
  , ("drop" , cmdDrop)
  , ("type" , cmdType)
  , ("show" , cmdShow)
  , ("set"  , cmdSet)
  , ("quit" , cmdQuit)
  , ("!"    , cmdBang)
  , ("config", cmdConfig)
  ]

---------------------------
-- run specific commands --
---------------------------

cmdHelp :: String -> Repl ()
cmdHelp _ = print
  "You can type or paste ShortCut code here to run it, same as in a script.\n\
  \There are also some extra commands:\n\n\
  \:help  to print this help text\n\
  \:load  to load a script (same as typing the file contents)\n\
  \:write to write the current script to a file\n\
  \:drop  to discard the current script and start fresh\n\
  \:quit  to discard the current script and exit the interpreter\n\
  \:type  to print the type of an expression\n\
  \:show  to print an expression along with its type\n\
  \:!     to run the rest of the line as a shell command"

-- TODO this is totally duplicating code from putAssign; factor out
-- TODO this shouldn't crash if a file referenced from the script doesn't exist!
cmdLoad :: String -> Repl ()
cmdLoad path = do
  -- (_, cfg) <- get
  cfg <- getConfig
  new <- liftIO $ iFile ([], cfg) path 
  case new of
    Left  e -> print $ show e
    Right n -> putScript n

-- TODO this needs to read a second arg for the var to be main?
--      or just tell people to define main themselves?
-- TODO replace showHack with something nicer
cmdSave :: String -> Repl ()
cmdSave path = do
  path' <- liftIO $ absolutize path
  -- get >>= \s -> liftIO $ writeFile path' $ showHack $ fst s
  getScript >>= \s -> liftIO $ writeFile path' $ show s
  -- where
    -- showHack = unlines . map prettyShow

cmdDrop :: String -> Repl ()
cmdDrop [] = putScript []
cmdDrop var = do
  -- (script, cfg) <- get
  scr <- getScript
  let v = CutVar var
  case lookup v scr of
    Nothing -> print $ "Var '" ++ var ++ "' not found"
    Just _  -> putScript $ delFromAL scr v

-- TODO show the type description here too once that's ready
--      (add to the pretty instance?)
cmdType :: String -> Repl ()
cmdType s = do
  -- (script, cfg) <- get
  scr <- getScript
  cfg <- getConfig
  print $ case iExpr (scr, cfg) s of
    -- Right expr -> prettyShow $ typeOf expr
    Right expr -> show $ typeOf expr
    Left  err  -> show err

cmdShow :: String -> Repl ()
-- cmdShow [] = getScript >>= \s -> liftIO $ mapM_ (putStrLn . prettyShow) s
cmdShow [] = getScript >>= \s -> liftIO $ mapM_ (putStrLn . show) s
cmdShow var = do
  scr <- getScript
  print $ case lookup (CutVar var) scr of
    Nothing -> "Var '" ++ var ++ "' not found"
    -- Just e  -> prettyShow e
    Just e  -> show e

cmdQuit :: String -> Repl ()
cmdQuit _ = mzero

cmdBang :: String -> Repl ()
cmdBang cmd = liftIO (runCommand cmd >>= waitForProcess) >> return ()

cmdSet :: String -> Repl ()
cmdSet = undefined
  -- TODO split string into first word and the rest
  -- TODO case statement for first word: verbose, workdir, tmpdir, script?
  -- TODO script sets the default for cmdSave?
  -- TODO don't bother with script yet; start with the obvious ones

-- TODO if no args, dump whole config by pretty-printing
-- TODO wow much staircase get rid of it
cmdConfig :: String -> Repl ()
cmdConfig s = do
  cfg <- getConfig
  let ws = words s
  if (length ws == 0)
    -- then (print (prettyShow cfg) >> return ()) -- TODO Pretty instance
    then (print (show cfg) >> return ()) -- TODO Pretty instance
    else if (length ws  > 2)
      then (print "too many variables" >> return ())
      -- TODO separate into get/set cases:
      else if (length ws == 1)
        then (cmdConfigShow (head ws))
        else (cmdConfigSet  (head ws) (last ws))

cmdConfigShow :: String -> Repl ()
cmdConfigShow key = getConfig >>= \cfg -> print $ fn cfg
  where
    fn = case key of
          "script"  -> (\c -> fromMaybe "none" $ cfgScript c)
          "verbose" -> (\c -> show $ cfgVerbose c)
          "workdir" -> cfgWorkDir
          "tmpdir"  -> cfgTmpDir
          _ -> \_ -> "no such config entry"

cmdConfigSet :: String -> String -> Repl ()
cmdConfigSet key val = do
  cfg <- getConfig
  case key of
    "script"  -> putConfig $ cfg { cfgScript  = Just val }
    "verbose" -> putConfig $ cfg { cfgVerbose = read val }
    "workdir" -> putConfig $ cfg { cfgWorkDir = val }
    "tmpdir"  -> putConfig $ cfg { cfgTmpDir  = val }
    -- _ -> throwError $ NoSuchVariable key
    _ -> fail $ "no such variable '" ++ key ++ "'"
