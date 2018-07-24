module ShortCut.Modules.Hmmer
  where

import Development.Shake
import ShortCut.Core.Types
import ShortCut.Modules.SeqIO (faa)
import ShortCut.Modules.Muscle (aln)
import ShortCut.Core.Compile.Basic (defaultTypeCheck, rSimple)
import ShortCut.Core.Paths (CutPath, fromCutPath)
import ShortCut.Core.Actions (debugA, wrappedCmdWrite, readLit, readLits, writeLits)
import Data.Scientific (formatScientific, FPFormat(..))
import Data.List (isPrefixOf, nub, sort)

cutModule :: CutModule
cutModule = CutModule
  { mName = "hmmer"
  , mFunctions = [hmmbuild, hmmsearch, extractHmmTargets]
  }

hmm :: CutType
hmm = CutType
  { tExt  = "hmm"
  , tDesc = "hidden markov model"
  -- , tShow = \_ _ f -> return $ "hidden markov model '" ++ f ++ "'"
  , tShow = defaultShow
  }

hht :: CutType
hht = CutType
  { tExt  = "hht"
  , tDesc = "HMMER hits table"
  , tShow = defaultShow -- TODO is this OK?
  }

hmmbuild :: CutFunction
hmmbuild = let name = "hmmbuild" in CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [aln] hmm
  , fTypeDesc  = name ++ " : aln -> hmm" -- TODO generate
  , fFixity    = Prefix
  , fRules     = rSimple aHmmbuild
  }

hmmsearch :: CutFunction
hmmsearch = let name = "hmmsearch" in CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [num, hmm, faa] hht
  , fTypeDesc  = name ++ " : num hmm faa -> hht" -- TODO generate
  , fFixity    = Prefix
  , fRules     = rSimple aHmmsearch
  }

-- TODO is it parallel?
-- TODO reverse order? currently matches blast fns but not native hmmbuild args
aHmmbuild :: CutConfig -> Locks -> [CutPath] -> Action ()
aHmmbuild cfg ref [out, fa] = do
  wrappedCmdWrite False True cfg ref out'' [fa'] [] [] "hmmbuild" [out', fa']
  where
    out'  = fromCutPath cfg out
    out'' = debugA cfg "aHmmbuild" out' [out', fa']
    fa'   = fromCutPath cfg fa
aHmmbuild _ _ args = error $ "bad argument to aHmmbuild: " ++ show args

-- TODO is it parallel?
-- TODO reverse order? currently matches blast fns but not native hmmsearch args
aHmmsearch :: CutConfig -> Locks -> [CutPath] -> Action ()
aHmmsearch cfg ref [out, e, hm, fa] = do
  eStr <- readLit cfg ref e'
  let eDec = formatScientific Fixed Nothing (read eStr) -- format as decimal
  wrappedCmdWrite False True cfg ref out'' [e', hm', fa'] [] []
    "hmmsearch" ["-E", eDec, "--tblout", out', hm', fa']
  where
    out'  = fromCutPath cfg out
    out'' = debugA cfg "aHmmsearch" out' [out', fa']
    e'    = fromCutPath cfg e
    hm'   = fromCutPath cfg hm
    fa'   = fromCutPath cfg fa
aHmmsearch _ _ args = error $ "bad argument to aHmmsearch: " ++ show args

extractHmmTargets :: CutFunction
extractHmmTargets = let name = "extract_hmm_targets" in CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [hht] (ListOf str)
  , fTypeDesc  = name ++ " : hht -> str.list"
  , fFixity    = Prefix
  , fRules     = rSimple $ aExtractHmm True 1
  }

-- TODO clean this up! it's pretty ugly
aExtractHmm :: Bool -> Int -> CutConfig -> Locks -> [CutPath] -> Action ()
aExtractHmm uniq n cfg ref [outPath, tsvPath] = do
  lits <- readLits cfg ref tsvPath'
  let lits'   = filter (\l -> not $ "#" `isPrefixOf` l) lits
      lits''  = if uniq then sort $ nub lits' else lits'
      lits''' = map (\l -> (words l) !! (n - 1)) lits''
  writeLits cfg ref outPath'' lits'''
  where
    outPath'  = fromCutPath cfg outPath
    outPath'' = debugA cfg "aExtractHmm" outPath' [show n, outPath', tsvPath']
    tsvPath'  = fromCutPath cfg tsvPath
aExtractHmm _ _ _ _ _ = error "bad arguments to aExtractHmm"
