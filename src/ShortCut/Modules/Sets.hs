module ShortCut.Modules.Sets where

-- TODO move this stuff to Core? (maybe split Compile into a couple modules?)

import Data.Set (Set, union, difference, intersection ,fromList, toList)
import Development.Shake
import ShortCut.Core.Paths (exprPath, fromCutPath, readPaths, writePaths, CutPath)
import ShortCut.Core.Compile.Basic (rBop, rExpr, typeError)
import ShortCut.Core.Types
import ShortCut.Core.Debug (debugRules, debugAction)
import Development.Shake.FilePath ((</>))
import ShortCut.Core.Util (resolveSymlinks)
-- import Path (fromCutPath cfg) -- TODO remove and use Path everywhere

cutModule :: CutModule
cutModule = CutModule
  { mName = "setops"
  , mFunctions =
    [ unionBop
    , unionFold
    , intersectionBop
    , intersectionFold
    , differenceBop
    ]
  }

-- a kludge to resolve the difference between load_* and load_*_each paths
-- TODO remove this or shunt it into Paths.hs or something!
canonicalLinks :: CutType -> [FilePath] -> IO [FilePath]
canonicalLinks rtn =
  if rtn `elem` [ListOf str, ListOf num]
    then return
    else \ps -> mapM resolveSymlinks ps

----------------------
-- binary operators --
----------------------

mkSetBop :: String -> (Set CutPath -> Set CutPath -> Set CutPath) -> CutFunction
mkSetBop name fn = CutFunction
  { fName      = name
  , fTypeCheck = bopTypeCheck
  , fFixity    = Infix
  , fRules  = rSetBop fn
  }

-- if the user gives two lists but of different types, complain that they must
-- be the same. if there aren't two lists at all, complain about that first
bopTypeCheck :: [CutType] -> Either String CutType
bopTypeCheck actual@[ListOf a, ListOf b]
  | a == b    = Right $ ListOf a
  | otherwise = Left $ typeError [ListOf a, ListOf a] actual
bopTypeCheck _ = Left "Type error: expected two lists of the same type"

-- apply a set operation to two lists (converted to sets first)
-- TODO if order turns out to be important in cuts, call them lists
rSetBop :: (Set CutPath -> Set CutPath -> Set CutPath)
     -> CutState -> CutExpr -> Rules ExprPath
rSetBop fn s@(_,cfg) e@(CutBop _ _ _ _ s1 s2) = do
  -- liftIO $ putStrLn "entering rSetBop"
  -- let fixLinks = liftIO . canonicalLinks (typeOf e)
  -- let fixLinks = canonicalLinks (typeOf e)
  let fixLinks = return
  (ExprPath p1, ExprPath p2, ExprPath p3) <- rBop s e (s1, s2)
  p3 %> aSetBop cfg fixLinks fn p1 p2
  return (ExprPath p3)
rSetBop _ _ _ = error "bad argument to rSetBop"

aSetBop :: CutConfig -> ([String] -> IO [String])
        -> (Set CutPath -> Set CutPath -> Set CutPath)
        -> FilePath -> FilePath -> FilePath -> Action ()
aSetBop cfg _ fn p1 p2 out = do
  need [p1, p2] -- this is required for parallel evaluation!
  -- lines1 <- liftIO . fixLinks =<< readFileLines p1
  -- lines2 <- liftIO . fixLinks =<< readFileLines p2
  paths1 <- readPaths cfg p1
  paths2 <- readPaths cfg p2
  -- putQuiet $ unwords [fnName, p1, p2, p3]
  let paths3 = fn (fromList paths1) (fromList paths2)
      out' = debugAction cfg "aSetBop" out [p1, p2, out]
  -- liftIO $ putStrLn $ "paths3: " ++ show paths3
  writePaths cfg out' $ toList paths3 -- TODO delete file on error (else it looks empty!)

unionBop :: CutFunction
unionBop = mkSetBop "|" union

differenceBop :: CutFunction
differenceBop = mkSetBop "~" difference

intersectionBop :: CutFunction
intersectionBop = mkSetBop "&" intersection

---------------------------------------------
-- functions that summarize lists of lists --
---------------------------------------------

mkSetFold :: String -> ([Set CutPath] -> Set CutPath) -> CutFunction
mkSetFold name fn = CutFunction
  { fName      = name
  , fTypeCheck = tSetFold
  , fFixity    = Prefix
  , fRules  = rSetFold fn
  }

tSetFold :: [CutType] -> Either String CutType
tSetFold [ListOf (ListOf x)] = Right $ ListOf x
tSetFold _ = Left "expecting a list of lists"

rSetFold :: ([Set CutPath] -> Set CutPath) -> CutState -> CutExpr -> Rules ExprPath
rSetFold fn s@(_,cfg) e@(CutFun _ _ _ _ [lol]) = do
  (ExprPath setsPath) <- rExpr s lol
  let oPath    = fromCutPath cfg $ exprPath s e
      oPath'   = cfgTmpDir cfg </> oPath
      oPath''  = debugRules cfg "rSetFold" e oPath
      fixLinks = canonicalLinks (typeOf e)
  oPath %> \_ -> aSetFold cfg fixLinks fn oPath' setsPath
  return (ExprPath oPath'')
rSetFold _ _ _ = error "bad argument to rSetFold"

aSetFold :: CutConfig
         -> ([String] -> IO [String])
         -> ([Set CutPath] -> Set CutPath)
         -> FilePath -> FilePath -> Action ()
aSetFold cfg _ fn oPath setsPath = do
  lists <- readPaths cfg setsPath
  let lists' = map (fromCutPath cfg) lists
  -- listContents  <- mapM (debugReadLines cfg) $ map (cfgTmpDir cfg </>) lists
  listContents  <- mapM (readPaths cfg) lists'
  -- listContents' <- liftIO $ mapM (liftIO . fixLinks) listContents
  -- liftIO $ putStrLn $ "listContents': " ++ show listContents'
  let sets = map fromList listContents
      oLst = toList $ fn sets
      oPath' = debugAction cfg "aSetFold" oPath [oPath, setsPath]
  writePaths cfg oPath' oLst

-- avoided calling it `all` because that's a Prelude function
intersectionFold :: CutFunction
intersectionFold = mkSetFold "all" $ foldr1 intersection

-- avoided calling it `any` because that's a Prelude function
unionFold :: CutFunction
unionFold = mkSetFold "any" $ foldr1 union
