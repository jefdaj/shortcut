{-# LANGUAGE ScopedTypeVariables #-}

{-|
This module "compiles" an expression it by translating it into a set of Shake
build rules. To actually run the rules, use `eval` in the Interpret module.

TODO add more descriptive runtime error for canonicalizePath failing b/c no file

TODO see if you can avoid making more than one absolute symlink per input file

TODO make systematically sure there's only one rule for each file

TODO pass tmpDir as a config option somehow, and verbosity

TODO why doesn't turning down the verbosity actually work?
-}

module OrthoLang.Core.Compile.Basic
  (

  -- * Expression compilers
    rExpr
  , rLit
  , rList
  , rListLits
  , rListPaths
  , rNamedFunction
  , rMacro

  -- * Script compilers
  , rRef
  , compileScript
  , rVar
  , rAssign

  -- * Function compilers for export
  , mkLoad
  , mkLoadList

  -- * Misc functions for export
  , curl
  , debugC
  , debugRules
  -- , defaultTypeCheck
  , typeError

  -- misc internal functions (TODO export them too?)
  -- , aLit
  -- , aLoad
  -- , aLoadHash
  -- , aLoadListLinks
  -- , aLoadListLits
  -- , aListLits
  -- , aListPaths
  -- , aVar
  -- , isURL
  -- , withInsertNewRulesDigests

  )
  where

-- TODO does turning of traces radically speed up the interpreter?

import Prelude hiding (error)
import OrthoLang.Debug
import Development.Shake
import Development.Shake.FilePath (isAbsolute)
import OrthoLang.Core.Types
import OrthoLang.Core.Pretty
import qualified Data.Map.Strict as M

import OrthoLang.Core.Paths (cacheDir, exprPath, unsafeExprPathExplicit, toPath,
                            fromPath, varPath, Path)

import Data.IORef                 (atomicModifyIORef', readIORef)
import Data.List                  (isPrefixOf, isInfixOf)
import Development.Shake.FilePath ((</>), (<.>), takeFileName)
import OrthoLang.Core.Actions      (runCmd, CmdDesc(..), traceA, debugA, need',
                                   readLit, readLits, writeLit, writeLits, hashContent,
                                   readLitPaths, writePaths, symlink)
import OrthoLang.Core.Sanitize     (hashIDsFile2, readIDs)
import OrthoLang.Util         (absolutize, resolveSymlinks, stripWhiteSpace,
                                   digest, removeIfExists, headOrDie, unlessExists)
import System.FilePath            (takeExtension)
import System.Exit                (ExitCode(..))
import System.Directory           (createDirectoryIfMissing)

import Data.Maybe (isJust, fromJust)

-- import OrthoLang.Core.Paths (insertNewRulesDigest)
import System.IO.Unsafe (unsafePerformIO)
import Control.Monad.Reader (ask)
import Control.Monad.Trans.Class (lift)


debugC :: Config -> String -> String -> a -> a
debugC cfg name msg rtn = trace ("core.compile." ++ name) msg rtn

-- TODO restrict to Expr?
-- TODO export?
-- TODO put in rExpr to catch everything at once? but misses which fn was called
debugRules :: (Pretty a, Show b) => Config -> String -> a -> b -> b
debugRules cfg name input out = debugC cfg name msg out
  where
    ren = render $ pPrint input
    msg = "\"" ++ ren ++ "' -> " ++ show out


------------------------------
-- compile the OrthoLang AST --
------------------------------

-- This should return the same outPath as the old RulesFns, without doing anything else.
-- TODO remove it once the new rules are all written
-- deprecatedRules :: GlobalEnv -> Expr -> Rules ExprPath
-- deprecatedRules s@(_, cfg, _, _, _) e = return $ ExprPath out'
--   where
--     out  = exprPath cfg dRef scr e
--     out' = fromPath cfg $ exprPath cfg dRef scr e

-- for functions with fNewRules, ignore fOldRules and return Nothing immediately. otherwise carry on as normal
-- TODO wait! it's the rules that might not need to be returned, not the path, right?
--            that actually makes it easy to use the same function types but not do any actual rules :D

-- TODO insert digests as they're compiled here, not as they're parsed
--      (because some are generated automatically, not parsed at all!)
-- TODO and put them into the state explicitly without this IORef hack

-- withInsertNewRulesDigests:: GlobalEnv -> [Expr] -> a -> a
-- withInsertNewRulesDigests s@(_,_,_,r) es a = unsafePerformIO $ do
--   mapM_ (insertNewRulesDigest s) es
--   (IDs {hExprs = ids}) <- readIORef r
--   print ids
--   return a

{-|
The main entry point for compiling any 'Expr'. Use this by default
unless you have a reason to delve into the more specific compilers below!

TODO remove the insert digests hack? or is this the main entry point for that too?

TODO are the extra rExpr steps needed in most cases, or only for rNamedFunction?
-}
rExpr :: RulesFn
rExpr s e@(Lit _ _ _      ) = rLit s e
rExpr s e@(Ref _ _ _ _    ) = rRef s e
rExpr s e@(Lst _ _ _   es) = mapM (rExpr s) es >> rList s e
rExpr s e@(Fun _ _ _ n es) = mapM (rExpr s) es >> rNamedFunction s e n -- TODO why is the map part needed?
-- TODO possible bug source: the list expr path + digest is never returned, even though it's compiled
rExpr s e@(Bop t r ds _ e1 e2) = mapM (rExpr s) [e1, e2, Lst t r ds [e1, e2]] >> rBop s e
rExpr _ (Com (CompiledExpr _ _ rules)) = rules

-- | Temporary hack to fix Bops
rBop :: RulesFn
rBop s e@(Bop t r ds _ e1 e2) = rExpr s es >> rExpr s fn
  where
    es = Lst t r ds [e1, e2] -- TODO (ListOf t)?
    fn = Fun t r ds (prefixOf e) [es]
rBop _ e = error "rBop" $ "called with non-Bop: \"" ++ render (pPrint e) ++ "\""

-- | This is in the process of being replaced with fNewRules,
--   so we ignore any function that already has that field written.
rNamedFunction :: Script -> Expr -> String -> Rules ExprPath
rNamedFunction s e@(Fun _ _ _ _ es) n = rNamedFunction' s e n -- TODO is this missing the map part above?
rNamedFunction _ _ n = error "rNamedFunction" $ "bad argument: " ++ n

rNamedFunction' scr expr name = do
  cfg  <- fmap fromJust getShakeExtraRules
  dRef <- fmap fromJust getShakeExtraRules
  case findFunction cfg name of
    Nothing -> error "rNamedFunction" $ "no such function \"" ++ name ++ "\""
    Just f  -> case fNewRules f of
                 NewNotImplemented -> if "load_" `isPrefixOf` fName f
                                        then (fOldRules f) scr $ setSalt 0 expr
                                        else (fOldRules f) scr expr
                 -- note that the rules themselves should have been added by 'newRules'
                 NewRules _ -> let p   = fromPath cfg $ exprPath cfg dRef scr expr
                                   res = ExprPath p
                               in return $ debugRules cfg "rNamedFunction'" expr res
                 -- TODO typecheck here to make sure the macro didn't mess anything up
                 NewMacro mFn -> rMacro cfg mFn scr expr

rMacro :: Config -> (Script -> Expr -> Expr) -> Script -> Expr -> Rules ExprPath
rMacro cfg mFn scr expr = rExpr scr $ debugRules cfg "rMacro" expr expr'
  where
    expr' = mFn scr expr

rAssign :: Script -> Assign -> Rules (Var, VarPath)
rAssign scr (var, expr) = do
  (ExprPath path) <- rExpr scr expr
  cfg <- fmap fromJust getShakeExtraRules
  path' <- rVar var expr $ toPath cfg path
  let res  = (var, path')
      res' = debugRules cfg "rAssign" (var, expr) res
  return res'

-- TODO how to fail if the var doesn't exist??
--      (or, is that not possible for a typechecked AST?)
-- TODO remove permHash
compileScript :: Script -> RepID -> Rules ResPath
compileScript scr _ = do
  -- TODO this can't be done all in parallel because they depend on each other,
  --      but can parts of it be parallelized? or maybe it doesn't matter because
  --      evaluating the code itself is always faster than the system commands
  rpaths <- mapM (rAssign scr) scr -- TODO is having scr be both an issue? 
  res <- case lookupResult rpaths of
    Nothing -> fmap (\(ExprPath p) -> p) $ rExpr scr $ fromJust $ lookupResult $ ensureResult scr
    Just r  -> fmap (\(VarPath  p) -> p) $ return r
  return $ ResPath res
  -- where
    -- p here is "result" + the permutation name/hash if there is one right?
    -- res = case permHash of
      -- Nothing -> "result"
      -- Just h  -> "result." ++ h

-- | Write a literal value (a 'str' or 'num') from OrthoLang source code to file
rLit :: RulesFn
rLit scr expr = do
  cfg  <- fmap fromJust getShakeExtraRules
  dRef <- fmap fromJust getShakeExtraRules
  let path  = exprPath cfg dRef scr expr -- absolute paths allowed!
      path' = debugRules cfg "rLit" expr $ fromPath cfg path
  path' %> \_ -> aLit expr path
  return (ExprPath path')

-- TODO take the path, not the expression?
-- TODO these actions all need to decode their dependencies from the outpath rather than the expression
aLit :: Expr -> Path -> Action ()
aLit expr out = do
  cfg <- fmap fromJust getShakeExtra
  let paths :: Expr -> FilePath
      paths (Lit _ _ p) = p
      paths _ = fail "bad argument to paths"
      ePath = paths expr
      out'  = fromPath cfg out
      out'' = traceA "aLit" out' [ePath, out']
  writeLit out'' ePath -- TODO too much dedup?

{-|
Lists written explicitly in the source code (not generated by function calls).
These use the 'Lst' constructor; generated lists come as 'Fun's
whose type is a @'ListOf' \<something\>@ instead.

TODO remove the insert digests hack
-}
rList :: RulesFn
rList s e@(Lst rtn _ _ es)
  | rtn `elem` [Empty, str, num] = rListLits  s e
  | otherwise                    = rListPaths s e
rList _ _ = error "rList" "bad arguemnt"

{-|
Special case for writing lists of literals ('str's or 'num's) in the source code.
For example:

@
nums = [1,2,3]
strs = ["one", "two", "three", "four"]
@

These have a variable number of arguments which is known at Rules-time. So we
fold over their digests to produce one main \"argument\" digest. All their
actual arguments are added to their 'hExprs' entry at the same time.

Note this is different from how function-generated lists of literals (or paths)
are handled, because their arguments won't be known until after the function
runs.

It's also different from how source code lists of non-literals are handled, in
order to match the format of function-generated lists of literals. It turns out
to be much more efficient for those to write one big multiline file than
thousands of small literals + one list of links pointing to them.

TODO can it be mostly unified with rListPaths digest-wise?

TODO what happens when you make a list of literals in two steps using links?
-}
rListLits :: RulesFn
rListLits scr e@(Lst _ _ _ exprs) = do
  litPaths <- mapM (rExpr scr) exprs
  cfg <- fmap fromJust getShakeExtraRules
  let litPaths' = map (\(ExprPath p) -> toPath cfg p) litPaths
  dRef <- fmap fromJust getShakeExtraRules
  let outPath  = exprPath cfg dRef scr e
      outPath' = debugRules cfg "rListLits" e $ fromPath cfg outPath
  outPath' %> \_ -> aListLits litPaths' outPath
  return (ExprPath outPath')
rListLits _ e = error "rListLits" $ "bad argument: " ++ show e

-- TODO put this in a cache dir by content hash and link there
aListLits :: [Path] -> Path -> Action ()
aListLits paths outPath = do
  cfg <- fmap fromJust getShakeExtra
  let out'   = fromPath cfg outPath
      out''  = traceA "aListLits" out' (out':paths')
      paths' = map (fromPath cfg) paths
  need' "core.compile.basic.aListLits" paths' -- TODO remove?
  lits <- mapM readLit paths'
  let lits' = map stripWhiteSpace lits -- TODO insert <<emptylist>> here?
  debugA "core.compile.basic.aListLits" $ "lits': " ++ show lits'
  writeLits out'' lits'

{-|
Regular case for writing a list of links to some other file type
(not literal 'str's or 'num's) in the source code. For example:

@
chlamy    = load_faa ...
athaliana = load_faa ...
pcc7942   = load_faa ...
greens = [chlamy, athaliana, pcc7942]
@

Like lists of literals, these also have a variable number of arguments which is
known at Rules-time. So we fold over their digests to produce one main
\"argument\" digest. All their actual arguments are added to their 'hExprs'
entry at the same time. Note this is different from how function-generated
lists of paths (or literals) are handled, because their arguments won't be
known until after the function runs.

TODO hash mismatch error here?
-}
rListPaths :: RulesFn
rListPaths scr e@(Lst rtn salt _ exprs) = do
  paths <- mapM (rExpr scr) exprs
  cfg  <- fmap fromJust getShakeExtraRules
  dRef <- fmap fromJust getShakeExtraRules
  let paths'   = map (\(ExprPath p) -> toPath cfg p) paths
      -- hash     = digest $ concat $ map digest paths'
      -- outPath  = unsafeExprPathExplicit cfg "list" (ListOf rtn) salt [hash]
      outPath  = exprPath cfg dRef scr e
      outPath' = debugRules cfg "rListPaths" e $ fromPath cfg outPath
  outPath' %> \_ -> aListPaths paths' outPath
  return (ExprPath outPath')
rListPaths _ _ = error "rListPaths" "bad argument"

aListPaths :: [Path] -> Path -> Action ()
aListPaths paths outPath = do
  cfg <- fmap fromJust getShakeExtra
  let out'   = fromPath cfg outPath
      out''  = traceA "aListPaths" out' (out':paths')
      paths' = map (fromPath cfg) paths -- TODO remove this
  need' "core.compile.basic.aListPaths" paths'
  paths'' <- liftIO $ mapM (resolveSymlinks $ Just $ cfgTmpDir cfg) paths'
  need' "core.compile.basic.aListPaths" paths''
  let paths''' = map (toPath cfg) paths'' -- TODO not working?
  writePaths out'' paths'''

-- return a link to an existing named variable
-- (assumes the var will be made by other rules)
rRef :: RulesFn
rRef _ e@(Ref _ _ _ var) = do
  cfg <- fmap fromJust getShakeExtraRules
  let ePath p = ExprPath $ debugRules cfg "rRef" e $ fromPath cfg p
  return $ ePath $ varPath cfg var e
    
rRef _ _ = fail "bad argument to rRef"

-- Creates a symlink from varname to expression file.
-- TODO unify with rLink2, rLoad etc?
-- TODO do we need both the Expr and ExprPath? seems like Expr would do
rVar :: Var -> Expr -> Path -> Rules VarPath
rVar var expr oPath = do
  cfg <- fmap fromJust getShakeExtraRules
  let vPath  = varPath cfg var expr
      vPath' = debugRules cfg "rVar" var $ fromPath cfg vPath
  vPath' %> \_ -> aVar vPath oPath
  return (VarPath vPath')

aVar :: Path -> Path -> Action ()
aVar vPath oPath = do
  alwaysRerun
  cfg <- fmap fromJust getShakeExtra
  let oPath'  = fromPath cfg oPath
      vPath'  = fromPath cfg vPath
      vPath'' = traceA "aVar" vPath [vPath', oPath']
  need' "core.compile.basic.aVar" [oPath']
  ref <- fmap fromJust getShakeExtra
  liftIO $ removeIfExists ref vPath'
  -- TODO should it sometimes symlink and sometimes copy?
  -- TODO before copying, think about how you might have to re-hash again!
  symlink vPath'' oPath
  -- ids' <- liftIO $ readIORef ids
  -- unhashIDsFile ' oPath vPath''
  where


------------------------------
-- [t]ypechecking functions --
------------------------------

-- TODO show the failing function here! which means reworking the Fun definitions a bit
-- TODO different text for failing Bops
typeError :: String -> [Type] -> [Type] -> String
typeError name expected actual =
  "Type mismatch :(\nThe function " ++ name ++
  " requires these inputs: "        ++ unwords (map show expected) ++
  "\nBut it was given these: "      ++ unwords (map show actual)

-- TODO this should fail for type errors like multiplying a list by a num!
-- TODO remove this entirely rather than trying to migrate it to the new model
--defaultTypeCheck :: String -> [Type] -> Type
--                 -> [Type] -> Either String Type
--defaultTypeCheck name expected returned actual =
--  if actual `typeSigsMatch` expected
--    then Right returned
--    else Left $ typeError name expected actual


--------------------------
-- links to input files --
--------------------------

{- Takes a string with the filepath to load. Creates a trivial expression file
 - that's just a symlink to the given path. These should be the only absolute
 - links, and the only ones that point outside the temp dir.
 - TODO still true?
 -}
mkLoad :: Bool -> String -> Type -> Function
mkLoad hashSeqIDs name rtn = Function
  { fOpChar = Nothing, fName = name
  -- , fTypeCheck = defaultTypeCheck name [str] rtn
  -- , fTypeDesc  = mkTypeDesc name [str] rtn
  , fInputs = [Exactly str]
  , fOutput =  Exactly rtn
  , fTags = []
  , fOldRules = rLoad hashSeqIDs
  , fNewRules = NewNotImplemented
  }

{- Like cLoad, except it operates on a list of strings. Note that you can also
 - load lists using cLoad, but it's not recommended because then you have to
 - write the list in a file, whereas this can handle literal lists in the
 - source code.
 -}
mkLoadList :: Bool -> String -> Type -> Function
mkLoadList hashSeqIDs name rtn = Function
  { fOpChar = Nothing, fName = name
  -- , fTypeCheck = defaultTypeCheck name [(ListOf str)] (ListOf rtn)
  -- , fTypeDesc  = mkTypeDesc name [(ListOf str)] (ListOf rtn)
  , fInputs = [Exactly (ListOf str)]
  , fOutput = Exactly (ListOf rtn)
  , fTags = []
  , fOldRules = rLoadList hashSeqIDs -- TODO different from src lists?
  , fNewRules = NewNotImplemented
  }

-- The paths here are a little confusing: expr is a str of the path we want to
-- link to. So after compiling it we get a path to *that str*, and have to read
-- the file to access it. Then we want to `ln` to the file it points to.
rLoad :: Bool -> RulesFn
rLoad hashSeqIDs scr e@(Fun _ _ _ _ [p]) = do
  (ExprPath strPath) <- rExpr scr p
  cfg  <- fmap fromJust getShakeExtraRules
  dRef <- fmap fromJust getShakeExtraRules
  let out  = exprPath cfg dRef scr e
      out' = fromPath cfg out
  out' %> \_ -> aLoad hashSeqIDs (toPath cfg strPath) out
  return (ExprPath out')
rLoad _ _ _ = fail "bad argument to rLoad"

-- TODO is running this lots of times at once the problem?
-- TODO see if shake exports code for only hashing when timestamps change
-- TODO remove ext? not sure it does anything
aLoadHash :: Bool -> Path -> String -> Action Path
aLoadHash hashSeqIDs src _ = do
  alwaysRerun
  -- liftIO $ putStrLn $ "aLoadHash " ++ show src
  cfg <- fmap fromJust getShakeExtra
  let src' = fromPath cfg src
  need' "core.compile.basic.aLoadHash" [src']
  md5 <- hashContent src -- TODO permission error here?
  let tmpDir'   = fromPath cfg $ cacheDir cfg "load" -- TODO should IDs be written to this + _ids.txt?
      hashPath' = tmpDir' </> md5 -- <.> ext
      hashPath  = toPath cfg hashPath'
  if not hashSeqIDs
    then symlink hashPath src
    else do
      let idsPath' = hashPath' <.> "ids"
          idsPath  = toPath cfg idsPath'

      unlessExists idsPath' $ hashIDsFile2 src hashPath

      let (Path k) = hashPath
          v = takeFileName src'
      newIDs <- readIDs idsPath
      ids <- fmap fromJust getShakeExtra
      liftIO $ atomicModifyIORef' ids $
        \h@(IDs {hFiles = f, hSeqIDs = s}) -> (h { hFiles  = M.insert k v f
                                                       , hSeqIDs = M.insert k newIDs s}, ())

  return hashPath

-- This is hacky, but should work with multiple protocols like http(s):// and ftp://
isURL :: String -> Bool
isURL s = "://" `isInfixOf` take 10 s

-- TODO move to Load module?
curl :: String -> Action Path
curl url = do
  cfg <- fmap fromJust getShakeExtra
  let cDir    = fromPath cfg $ cacheDir cfg "curl"
      outPath = cDir </> digest url
  liftIO $ createDirectoryIfMissing True cDir
  runCmd $ CmdDesc
    { cmdBinary = "download.sh"
    , cmdArguments = [outPath, url]
    , cmdFixEmpties = False
    , cmdParallel = False
    , cmdInPatterns = []
    , cmdOutPath = outPath
    , cmdExtraOutPaths = []
    , cmdSanitizePaths = []
    , cmdOptions = []
    , cmdExitCode = ExitSuccess
    , cmdRmPatterns = [outPath]
    }
  return $ toPath cfg outPath

aLoad :: Bool -> Path -> Path -> Action ()
aLoad hashSeqIDs strPath outPath = do
  alwaysRerun
  cfg <- fmap fromJust getShakeExtra
  let strPath'  = fromPath cfg strPath
      outPath'  = fromPath cfg outPath
      outPath'' = traceA "aLoad" outPath [strPath', outPath']
      toAbs line = if isAbsolute line
                     then line
                     else cfgWorkDir cfg </> line
  need' "core.compile.basic.aLoad" [strPath']
  pth <- fmap (headOrDie "read lits in aLoad failed") $ readLits strPath' -- TODO safer!
  -- liftIO $ putStrLn $ "pth: " ++ pth
  pth' <- if isURL pth
            then curl pth
            else fmap (toPath cfg . toAbs) $ liftIO $ resolveSymlinks (Just $ cfgTmpDir cfg) pth
  -- liftIO $ putStrLn $ "pth': " ++ show pth'
  -- src' <- if isURL pth
            -- then curl ref pth
            -- else 
  -- liftIO $ putStrLn $ "src': " ++ src'
  -- debugA $ "aLoad src': \"" ++ src' ++ "\""
  -- debugA $ "aLoad outPath': \"" ++ outPath' ++ "\""
  -- TODO why doesn't this rerun?
  hashPath <- aLoadHash hashSeqIDs pth' (takeExtension outPath')
  -- let hashPath'    = fromPath cfg hashPath
      -- hashPathRel' = ".." </> ".." </> makeRelative (cfgTmpDir cfg) hashPath'
  symlink outPath'' hashPath
  -- trackWrite' [outPath'] -- TODO WTF? why does this not get called by symlink?
  where

rLoadList :: Bool -> RulesFn
rLoadList hashSeqIDs s e@(Fun (ListOf r) _ _ _ [es])
  | r `elem` [str, num] = rLoadListLits s es
  | otherwise = rLoadListPaths hashSeqIDs s e
rLoadList _ _ _ = fail "bad arguments to rLoadList"

-- special case for lists of str and num
-- TODO remove rtn and use (typeOf expr)?
-- TODO is it different from rLink? seems like it's just a copy/link operation...
-- TODO don't need to hash seqids here right?
-- TODO need to readLitPaths?
rLoadListLits :: RulesFn
rLoadListLits scr expr = do
  (ExprPath litsPath') <- rExpr scr expr
  cfg  <- fmap fromJust getShakeExtraRules
  dRef <- fmap fromJust getShakeExtraRules
  let outPath  = exprPath cfg dRef scr expr
      outPath' = fromPath cfg outPath
      litsPath = toPath cfg litsPath'
  outPath' %> \_ -> aLoadListLits outPath litsPath
  return (ExprPath outPath')
  where

-- TODO have to listLitPaths here too?
aLoadListLits :: Path -> Path -> Action ()
aLoadListLits outPath litsPath = do
  cfg  <- fmap fromJust getShakeExtra
  let litsPath' = fromPath cfg litsPath
      outPath'  = fromPath cfg outPath
      out       = traceA "aLoadListLits" outPath' [outPath', litsPath']
  lits  <- readLits litsPath'
  lits' <- liftIO $ mapM absolutize lits
  writeLits out lits'

-- regular case for lists of any other file type
-- TODO hash mismatch here?
rLoadListPaths :: Bool -> RulesFn
rLoadListPaths hashSeqIDs scr e@(Fun rtn salt _ _ [es]) = do
  (ExprPath pathsPath) <- rExpr scr es
  -- let hash     = digest $ toPath cfg pathsPath
  --     outPath  = unsafeExprPathExplicit cfg "list" rtn salt [hash]
  cfg  <- fmap fromJust getShakeExtraRules
  dRef <- fmap fromJust getShakeExtraRules
  let outPath  = exprPath cfg dRef scr e
      outPath' = fromPath cfg outPath
  outPath' %> \_ -> aLoadListLinks hashSeqIDs (toPath cfg pathsPath) outPath
  return (ExprPath outPath')
rLoadListPaths _ _ _ = fail "bad arguments to rLoadListPaths"

aLoadListLinks :: Bool -> Path -> Path -> Action ()
aLoadListLinks hashSeqIDs pathsPath outPath = do
  -- Careful! The user will write paths relative to workdir and those come
  -- through as a (ListOf str) here; have to read as Strings and convert to
  -- Paths
  -- TODO this should be a macro expansion in the loader fns rather than a basic rule!
  -- alwaysRerun -- TODO does this help?
  cfg <- fmap fromJust getShakeExtra
  let outPath'   = fromPath cfg outPath
      pathsPath' = fromPath cfg pathsPath
      out = traceA "aLoadListLinks" outPath' [outPath', pathsPath']
  paths <- readLitPaths pathsPath'
  let paths' = map (fromPath cfg) paths
  paths'' <- liftIO $ mapM (resolveSymlinks $ Just $ cfgTmpDir cfg) paths'
  let paths''' = map (toPath cfg) paths''
  hashPaths <- mapM (\p -> aLoadHash hashSeqIDs p
                         $ takeExtension $ fromPath cfg p) paths'''
  let hashPaths' = map (fromPath cfg) hashPaths
  -- debugA $ "about to need: " ++ show paths''
  need' "core.compile.basic.aLoadListLinks" hashPaths'
  writePaths out hashPaths
