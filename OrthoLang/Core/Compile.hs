module OrthoLang.Core.Compile
  ( aSimpleScript
  , aSimpleScriptNoFix
  , aSimpleScriptPar
  -- , applyList2
  , compose1
  , compileScript
  , curl
  , debugC
  , debugRules
  , defaultTypeCheck
  , map3of3
  , mkLoad
  , mkLoadList
  , newBop
  , newFnA1
  , newFnA2
  , newFnA3
  , newMacro
  , newRules
  , MacroExpansion
  -- , rBop
  , rExpr
  , rFun3
  , rMap
  , rMapSimpleScript
  , rMapTmps
  , rSimple
  , rSimpleScript
  , rSimpleScriptPar
  , rSimpleTmp
  , typeError
  )
  where

import OrthoLang.Core.Compile.Basic
import OrthoLang.Core.Compile.Simple
import OrthoLang.Core.Compile.Map
import OrthoLang.Core.Compile.Map2
-- import OrthoLang.Core.Compile.Repeat
import OrthoLang.Core.Compile.Compose
import OrthoLang.Core.Compile.NewRules
