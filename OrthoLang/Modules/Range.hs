{-# LANGUAGE QuasiQuotes #-}

module OrthoLang.Modules.Range
  where

import Development.Shake
import OrthoLang.Core.Types

import System.FilePath ((<.>))
import OrthoLang.Core.Compile (defaultTypeCheck, rExpr)
import OrthoLang.Core.Actions (readLit, CmdDesc(..), runCmd)
import OrthoLang.Core.Paths (exprPath, fromPath)
import System.Exit (ExitCode(..))

orthoLangModule :: Module
orthoLangModule = Module
  { mName = "Range"
  , mDesc = "Generate ranges of numbers"
  , mTypes = [num]
  , mFunctions =
    [ mkRangeFn "range_add"      3
    , mkRangeFn "range_exponent" 4
    , mkRangeFn "range_integers" 2
    , mkRangeFn "range_length"   3
    , mkRangeFn "range_multiply" 3
    ]
  }

mkRangeFn :: String -> Int -> Function
mkRangeFn name nArgs =  Function
  { fOpChar = Nothing, fName = name
  , fTypeCheck = defaultTypeCheck (take nArgs $ repeat num) (ListOf num)
  , fTypeDesc  = mkTypeDesc name  (take nArgs $ repeat num) (ListOf num)
  ,fTags = []
  , fNewRules = Nothing, fOldRules = rRange
  }

-- TODO put somewhere as the standard way to construct an rSimpleScript that takes numbers?
rRange :: RulesFn
rRange st@(_, cfg, ref, _) e@(Fun _ _ _ name args) = do
  let out = exprPath st e
      out' = fromPath cfg out
  argPaths <- fmap (map (\(ExprPath p) -> p)) $ mapM (rExpr st) args
  out' %> \_ -> do
    as <- mapM (readLit cfg ref) argPaths
    runCmd cfg ref $ CmdDesc
      { cmdBinary = name <.> "R"
      , cmdArguments = out':as
      , cmdFixEmpties = False
      , cmdParallel = False
      , cmdOptions = []
      , cmdInPatterns = as
      , cmdOutPath = out'
      , cmdExtraOutPaths = []
      , cmdSanitizePaths = []
      , cmdExitCode = ExitSuccess
      , cmdRmPatterns = [out']
      }
  return $ ExprPath out'
rRange _ e = error $ "bad argument to rRange: " ++ show e
