module ShortCut.Modules.Sets where

-- TODO move this stuff to Core? (maybe split Compile into a couple modules?)

import Data.Set (Set, union, difference, intersection ,fromList, toList)
import Development.Shake
import ShortCut.Core.Paths   (exprPath)
import ShortCut.Core.Compile (cBop, cExpr)
import ShortCut.Core.ModuleAPI (typeError)
import ShortCut.Core.Types
import ShortCut.Core.Debug (debugReadLines, debugWriteLines,
                            debugCompiler)
import Development.Shake.FilePath ((</>))
import ShortCut.Core.Util (resolveSymlinks)

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
-- TODO is it deterministic?
canonicalLinks :: CutType -> [FilePath] -> IO [FilePath]
canonicalLinks rtn =
  if rtn `elem` [SetOf str, SetOf num]
    then return
    else \ps -> mapM resolveSymlinks ps

----------------------
-- binary operators --
----------------------

mkSetBop :: String -> (Set String -> Set String -> Set String) -> CutFunction
mkSetBop name fn = CutFunction
  { fName      = name
  , fTypeCheck = bopTypeCheck
  , fFixity    = Infix
  , fCompiler  = cSetBop fn
  }

-- if the user gives two lists but of different types, complain that they must
-- be the same. if there aren't two lists at all, complain about that first
bopTypeCheck :: [CutType] -> Either String CutType
bopTypeCheck actual@[SetOf a, SetOf b]
  | a == b    = Right $ SetOf a
  | otherwise = Left $ typeError [SetOf a, SetOf a] actual
bopTypeCheck _ = Left "Type error: expected two lists of the same type"

-- apply a set operation to two lists (converted to sets first)
-- TODO if order turns out to be important in cuts, call them lists
cSetBop :: (Set String -> Set String -> Set String)
     -> CutState -> CutExpr -> Rules ExprPath
cSetBop fn s e@(CutBop extn _ _ _ s1 s2) = do
  -- liftIO $ putStrLn "entering cSetBop"
  let fixLinks = liftIO . canonicalLinks (typeOf e)
  (ExprPath p1, ExprPath p2, ExprPath p3) <- cBop s extn e (s1, s2)
  p3 %> \out -> do
    need [p1, p2] -- this is required for parallel evaluation!
    lines1 <- fixLinks =<< readFileLines p1
    lines2 <- fixLinks =<< readFileLines p2
    -- putQuiet $ unwords [fnName, p1, p2, p3]
    let lines3 = fn (fromList lines1) (fromList lines2)
    writeFileLines out $ toList lines3
  return (ExprPath p3)
cSetBop _ _ _ = error "bad argument to cSetBop"

unionBop :: CutFunction
unionBop = mkSetBop "|" union

differenceBop :: CutFunction
differenceBop = mkSetBop "~" difference

intersectionBop :: CutFunction
intersectionBop = mkSetBop "&" intersection

---------------------------------------------
-- functions that summarize lists of lists --
---------------------------------------------

mkSetFold :: String -> ([Set String] -> Set String) -> CutFunction
mkSetFold name fn = CutFunction
  { fName      = name
  , fTypeCheck = tSetFold
  , fFixity    = Prefix
  , fCompiler  = cSetFold fn
  }

tSetFold :: [CutType] -> Either String CutType
tSetFold [SetOf (SetOf x)] = Right $ SetOf x
tSetFold _ = Left "expecting a list of lists"

cSetFold :: ([Set String] -> Set String) -> CutState -> CutExpr -> Rules ExprPath
cSetFold fn s@(_,cfg) e@(CutFun _ _ _ _ [lol]) = do
  (ExprPath setsPath) <- cExpr s lol
  let (ExprPath oPath) = exprPath cfg True e []
      oPath' = debugCompiler cfg "cSetFold" e oPath
      fixLinks = liftIO . canonicalLinks (typeOf e)
  oPath %> \_ -> do
    lists <- debugReadLines cfg setsPath
    listContents  <- mapM (debugReadLines cfg) $ map (cfgTmpDir cfg </>) lists
    listContents' <- liftIO $ mapM fixLinks listContents
    -- liftIO $ putStrLn $ "listContents': " ++ show listContents'
    let sets = map fromList listContents'
        oLst = toList $ fn sets
    debugWriteLines cfg oPath oLst
  return (ExprPath oPath')
cSetFold _ _ _ = error "bad argument to cSetFold"

-- avoided calling it `all` because that's a Prelude function
intersectionFold :: CutFunction
intersectionFold = mkSetFold "all" $ foldr1 intersection

-- avoided calling it `any` because that's a Prelude function
unionFold :: CutFunction
unionFold = mkSetFold "any" $ foldr1 union
