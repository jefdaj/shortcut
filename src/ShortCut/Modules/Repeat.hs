module ShortCut.Modules.Repeat where

-- TODO which parts of this should go in Core/Repeat.hs?
-- TODO debug transformations too!

import Development.Shake
import ShortCut.Core.Types
import ShortCut.Core.Compile.Basic (rExpr, debugRules, aScores)
import ShortCut.Core.Compile.Repeat
import ShortCut.Core.Paths (toCutPath, fromCutPath, exprPath)

import Data.Maybe      (fromJust)
import Data.Scientific (Scientific(), toBoundedInteger)

cutModule :: CutModule
cutModule = CutModule
  { mName = "repeat"
  , mFunctions =
    [ repeatEach -- TODO export this from the Core directly?
    , repeatN
    , scoreRepeats
    ]
  }

-----------------------------------------------------
-- repeat without permutation (to test robustness) --
-----------------------------------------------------

repeatN :: CutFunction
repeatN = CutFunction
  { fName      = "repeat"
  , fFixity    = Prefix
  , fTypeCheck = tRepeatN
  , fTypeDesc  = "repeat : <outputvar> <inputvar> num -> <output>.list"
  , fRules     = rRepeatN
  }

-- takes a result type, a starting type, and an int,
-- and returns a list of the result var type. start type can be whatever
-- TODO does num here refer to actual num, or is it shadowing it?
tRepeatN :: [CutType] -> Either String CutType 
tRepeatN [rType, _, n] | n == num = Right $ ListOf rType
tRepeatN _ = Left "invalid args to repeatN"

readSciInt :: String -> Int
readSciInt s = case toBoundedInteger (read s :: Scientific) of
  Nothing -> error $ "Not possible to repeat something " ++ s ++ " times."
  Just n  -> n

-- TODO is the bug here? might need to convert string -> sci -> int
extractNum :: CutScript -> CutExpr -> Int
extractNum _   (CutLit x _ n) | x == num = readSciInt n
extractNum scr (CutRef _ _ _ v) = extractNum scr $ fromJust $ lookup v scr
extractNum _ _ = error "bad argument to extractNum"

-- takes a result expression to re-evaluate, a variable to repeat and start from,
-- and a number of reps. returns a list of the result var re-evaluated that many times
-- can be read as "evaluate resExpr starting from subVar, repsExpr times"
-- TODO error if subVar not in (depsOf resExpr)
-- TODO is this how the salts should work?
rRepeatN :: CutState -> CutExpr -> Rules ExprPath
rRepeatN s@(scr,_,_) (CutFun t salt deps name [resExpr, subVar@(CutRef _ _ _ v), repsExpr]) =
  rRepeatEach s (CutFun t salt deps name [resExpr, subVar, subList])
  where
    subExpr = fromJust $ lookup v scr
    nReps   = extractNum scr repsExpr
    subs    = zipWith setSalt [salt .. salt+nReps-1] (repeat subExpr)
    subList = CutList (typeOf subExpr) 0 (depsOf subExpr) subs
rRepeatN _ _ = error "bad argument to rRepeatN"

-----------------------------------------------------
-- repeat_each and score the inputs by the outputs --
-----------------------------------------------------

-- (No need to score repeatN because it already produces a num.list)

scoreRepeats :: CutFunction
scoreRepeats = CutFunction
  { fName      = name
  , fFixity    = Prefix
  , fTypeCheck = tScoreRepeats
  , fTypeDesc  = name ++ " : <outputnum> <inputvar> <inputlist> -> <input>.scores"
  , fRules     = rScoreRepeats
  }
  where
    name = "score_repeats"

tScoreRepeats :: [CutType] -> Either String CutType 
tScoreRepeats [n1, _, (ListOf n2)] | n1 == num && n2 == num = Right $ ScoresOf num
tScoreRepeats _ = Left "invalid args to scoreRepeats"

rScoreRepeats :: CutState -> CutExpr -> Rules ExprPath
rScoreRepeats s@(_,cfg,ref) expr@(CutFun _ _ _ _ (resExpr:_:subList:[])) = do
  inputs <- rExpr s subList
  scores <- rRepeatEach s expr
  let eType   = typeOf resExpr
      hack    = \(ExprPath p) -> toCutPath cfg p -- TODO remove! but how?
      inputs' = hack inputs
      scores' = hack scores
  outPath' %> \_ -> aScores cfg ref scores' inputs' eType outPath
  return $ ExprPath outPath'
  where
    outPath  = exprPath s expr
    outPath' = debugRules cfg "rScoreRepeats" expr $ fromCutPath cfg outPath
rScoreRepeats _ expr = error $ "bad argument to rScoreRepeats: " ++ show expr

-- for reference:
-- rRepeatEach :: RulesFn -- aka CutState -> CutExpr -> Rules ExprPath
-- rRepeatEach s@(scr,cfg,ref) expr@(CutFun _ _ _ _ (resExpr:(CutRef _ _ _ subVar):subList:[])) = do
--   subPaths <- rExpr s subList
--   let subExprs = extractExprs scr subList
--   resPaths <- mapM (cRepeat s resExpr subVar) subExprs
--   let subPaths' = (\(ExprPath p) -> toCutPath cfg p) subPaths
--       resPaths' = map (\(ExprPath p) -> toCutPath cfg p) resPaths
--       outPath   = exprPath s expr
--       outPath'  = debugRules cfg "rRepeatEach" expr $ fromCutPath cfg outPath
--   outPath' %> \_ ->
--     let actFn = if typeOf expr `elem` [ListOf str, ListOf num]
--                   then aRepeatEachLits (typeOf expr)
--                   else aRepeatEachLinks
--     in actFn cfg ref outPath subPaths' resPaths'
--   return (ExprPath outPath')
-- rRepeatEach _ expr = error $ "bad argument to rRepeatEach: " ++ show expr
