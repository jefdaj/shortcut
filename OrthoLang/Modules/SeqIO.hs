-- TODO rename something more general like SeqUtils?

module OrthoLang.Modules.SeqIO where

import Development.Shake

import OrthoLang.Types
import OrthoLang.Interpreter

import System.FilePath             ((</>), (<.>), takeDirectory, takeFileName)
import System.Directory            (createDirectoryIfMissing)
import OrthoLang.Modules.Load       (mkLoad, mkLoadPath, mkLoadEach, mkLoadPathEach, mkLoadGlob)
import System.Exit                 (ExitCode(..))
import Data.Maybe (fromJust)
import Data.List.Utils (replace)

olModule :: Module
olModule = Module
  { mName = "SeqIO"
  , mDesc = "Sequence file manipulations using BioPython's SeqIO"
  , mTypes = [gbk, faa, fna]
  , mGroups = [fa]
  , mEncodings = []
  , mRules = []
  , mFunctions =
    [ gbkToFaaRawIDs, gbkToFaaRawIDsEach, gbkToFaa, gbkToFaaEach
    , gbkToFnaRawIDs, gbkToFnaRawIDsEach, gbkToFna, gbkToFnaEach
    , extractSeqs   , extractSeqsEach
    , extractIds    , extractIdsEach
    , translate     , translateEach
    , mkConcat fna  , mkConcatEach fna -- TODO pull these apart too
    , mkConcat faa  , mkConcatEach faa -- TODO pull these apart too
    , splitFasta faa, splitFastaEach faa
    , splitFasta fna, splitFastaEach fna
    , loadFna, loadFnaPath, loadFnaEach, loadFnaPathEach, loadFnaGlob
    , loadFaa, loadFaaPath, loadFaaEach, loadFaaPathEach, loadFaaGlob
    , loadGbk, loadGbkPath, loadGbkEach, loadGbkPathEach, loadGbkGlob
    -- TODO combo that loads multiple fnas or faas and concats them?
    -- TODO combo that loads multiple gbks -> fna or faa?
    ]
  }

loadFna         = mkLoad         True "load_fna"           (Exactly fna)
loadFnaPath     = mkLoadPath     True "load_fna_path"      (Exactly fna)
loadFnaEach     = mkLoadEach     True "load_fna_each"      (Exactly fna)
loadFnaPathEach = mkLoadPathEach True "load_fna_path_each" (Exactly fna)
loadFnaGlob     = mkLoadGlob          "load_fna_glob"       loadFnaEach

loadFaa         = mkLoad         True "load_faa"           (Exactly faa)
loadFaaPath     = mkLoadPath     True "load_faa_path"      (Exactly faa)
loadFaaEach     = mkLoadEach     True "load_faa_each"      (Exactly faa)
loadFaaPathEach = mkLoadPathEach True "load_faa_path_each" (Exactly faa)
loadFaaGlob     = mkLoadGlob          "load_faa_glob"       loadFaaEach

loadGbk         = mkLoad         False "load_gbk"           (Exactly gbk)
loadGbkPath     = mkLoad         False "load_gbk_path"      (Exactly gbk)
loadGbkEach     = mkLoadEach     False "load_gbk_each"      (Exactly gbk)
loadGbkPathEach = mkLoadPathEach False "load_gbk_path_each" (Exactly gbk)
loadGbkGlob     = mkLoadGlob           "load_gbk_glob"       loadGbkEach

gbk :: Type
gbk = Type
  { tExt  = "gbk"
  , tDesc = "Genbank files"
  , tShow = defaultShow
  }

fa :: TypeGroup
fa = TypeGroup
  { tgExt = "fa"
  , tgDesc  = "FASTA nucleic OR amino acid"
  , tgMembers = [Exactly fna, Exactly faa]
  }

faa :: Type
faa = Type
  { tExt  = "faa"
  , tDesc = "FASTA amino acid"
  , tShow = defaultShow
  }

fna :: Type
fna = Type
  { tExt  = "fna"
  , tDesc = "FASTA nucleic acid"
  , tShow = defaultShow
  }

--------------
-- gbk_to_* --
--------------

-- TODO should these automatically fill in the "CDS" string?

gbkToFaa :: Function
gbkToFaa = newExprExpansion "gbk_to_faa" [Exactly str, Exactly gbk] (Exactly faa) mGbkToFaa [ReadsFile]

mGbkToFaa :: ExprExpansion
mGbkToFaa _ _ (Fun r _ ds n [s, g]) = Fun r Nothing ds "load_faa_path" [Fun r Nothing ds (n ++ "_rawids") [s, g]]
mGbkToFaa _ _ e = error "modules.seqio.mGbkToFaa" $ "bad argument: " ++ show e

gbkToFaaRawIDs :: Function
gbkToFaaRawIDs = newFnA2
  "gbk_to_faa_rawids"
  (Exactly str, Exactly gbk)
  (Exactly faa)
  (aGenbankToFasta faa "aa")
  [Hidden]

gbkToFna :: Function
gbkToFna = newExprExpansion "gbk_to_fna" [Exactly str, Exactly gbk] (Exactly fna) mGbkToFna [ReadsFile]

mGbkToFna :: ExprExpansion
mGbkToFna _ _ (Fun r _ ds n [s, g]) = Fun r Nothing ds "load_fna_path" [Fun r Nothing ds (n ++ "_rawids") [s, g]]
mGbkToFna _ _ e = error "modules.seqio.mGbkToFna" $ "bad argument: " ++ show e

gbkToFnaRawIDs :: Function
gbkToFnaRawIDs = newFnA2
  "gbk_to_fna_rawids"
  (Exactly str, Exactly gbk)
  (Exactly fna)
  (aGenbankToFasta fna "nt") -- TODO add --qualifiers all?
  [Hidden]

gbkToFaaEach :: Function
gbkToFaaEach = newExprExpansion "gbk_to_faa_each" [Exactly str, Exactly $ ListOf gbk] (Exactly $ ListOf faa) mGbkToFaaEach [ReadsFile]

mGbkToFaaEach :: ExprExpansion
mGbkToFaaEach _ _ (Fun r _ ds n [s, g]) = Fun r Nothing ds "load_faa_path_each" [Fun r Nothing ds (replace "_each" "_rawids_each" n) [s, g]]
mGbkToFaaEach _ _ e = error "modules.seqio.mGbkToFaaEach" $ "bad argument: " ++ show e

gbkToFaaRawIDsEach :: Function
gbkToFaaRawIDsEach = newFnA2
  "gbk_to_faa_rawids_each"
  (Exactly str, Exactly $ ListOf gbk)
  (Exactly $ ListOf faa)
  (newMap2of2 "gbk_to_faa_rawids")
  [Hidden]

gbkToFnaEach :: Function
gbkToFnaEach = newExprExpansion "gbk_to_fna_each" [Exactly str, Exactly $ ListOf gbk] (Exactly $ ListOf fna) mGbkToFnaEach [ReadsFile]

mGbkToFnaEach :: ExprExpansion
mGbkToFnaEach _ _ (Fun r _ ds n [s, g]) = Fun r Nothing ds "load_fna_path_each" [Fun r Nothing ds (replace "_each" "_rawids_each" n) [s, g]]
mGbkToFnaEach _ _ e = error "modules.seqio.mGbkToFnaEach" $ "bad argument: " ++ show e

gbkToFnaRawIDsEach :: Function
gbkToFnaRawIDsEach = newFnA2
  "gbk_to_fna_rawids_each"
  (Exactly str, Exactly $ ListOf gbk)
  (Exactly $ ListOf fna)
  (newMap2of2 "gbk_to_fna_rawids")
  [Hidden]

-- TODO error if no features extracted since it probably means a wrong ft string
-- TODO silence the output? or is it helpful?
aGenbankToFasta :: Type -> String -> NewAction2
aGenbankToFasta rtn st (ExprPath outPath') ftPath' faPath' = do
  cfg <- fmap fromJust getShakeExtra
  let loc = "modules.seqio.aGenbankToFasta"
      exprDir'  = tmpdir cfg </> "exprs"
      tmpDir'   = fromPath loc cfg $ cacheDir cfg "seqio"
      outDir'   = exprDir' </> "load_" ++ ext rtn
      outPath'' = traceA loc outPath' [outPath', faPath']
  ft <- readLit loc ftPath'
  let ft' = if ft  == "cds" then "CDS" else ft
      (st', extraArgs) = if ft' == "whole" then ("whole", ["--annotations", "all"]) else (st, [])
      args = [ "--in_file", faPath'
             , "--out_file", outPath'
             , "--sequence_type", st'
             , "--feature_type", ft'] ++ extraArgs
  liftIO $ createDirectoryIfMissing True tmpDir'
  liftIO $ createDirectoryIfMissing True outDir'
  runCmd $ CmdDesc
    { cmdBinary = "genbank_to_fasta.py"
    , cmdArguments = args
    , cmdFixEmpties = False
    , cmdParallel = False
    , cmdOptions = []
    , cmdInPatterns = [faPath']
    , cmdNoNeedDirs = []
    , cmdOutPath = outPath'
    , cmdExtraOutPaths = []
    , cmdSanitizePaths = [outPath']
    , cmdExitCode = ExitSuccess
    , cmdRmPatterns = [outPath'']
    }

------------------------
-- extract_ids(_each) --
------------------------

-- TODO also extract them from genbank files

extractIds :: Function
extractIds = newFnS1
  "extract_ids"
  (Some fa "any fasta file")
  (Exactly $ ListOf str)
  "extract_ids.py"
  []
  id

extractIdsEach :: Function
extractIdsEach = newFnA1
  "extract_ids_each"
  (ListSigs $ Some fa "any fasta file")
  (Exactly $ ListOf $ ListOf str)
  (newMap1of1 "extract_ids")
  []

-------------------------
-- extract_seqs(_each) --
-------------------------

-- TODO also extract them from genbank files

extractSeqs :: Function
extractSeqs = newFnA2
  "extract_seqs"
  (Some fa "any fasta file", Exactly $ ListOf str)
  (Some fa "any fasta file")
  aExtractSeqs
  [] -- TODO tag for "re-load output"?

{-|
This is a little more complicated than it would seem because users will
provide a list of actual seqids, and we need to look up their hashes to extract
the hash-named ones from the previously-sanitized fasta file.
-}
aExtractSeqs :: NewAction2
aExtractSeqs out inFa inList = do
  cfg <- fmap fromJust getShakeExtra
  let loc = "modules.seqio.aExtractSeqs"
      tmp  = fromPath loc cfg $ cacheDir cfg "seqio"
      ids  = tmp </> digest loc (toPath loc cfg inList) <.> "txt"
      ids' = toPath loc cfg ids
  -- TODO these should be the seqid_... ids themselves, not unhashed?
  -- unhashIDsFile (toPath loc cfg inList) ids -- TODO implement as a macro?
  aNewRulesS2 "extract_seqs.py" id out inFa inList

-- TODO does this one make sense? is the mapping right?
extractSeqsEach :: Function
extractSeqsEach = newFnA2
  "extract_seqs_each"
  (Some fa "any fasta file", Exactly $ ListOf $ ListOf str)
  (ListSigs $ Some fa "any fasta file")
  (newMap2of2 "extract_seqs")
  []

----------------------
-- translate(_each) --
----------------------

translate :: Function
translate = newFnS1
  "translate"
  (Exactly fna)
  (Exactly faa)
  "translate.py"
  [ReadsFile]
  id

translateEach :: Function
translateEach = newFnA1
  "translate_each"
  (Exactly $ ListOf fna)
  (Exactly $ ListOf faa)
  (newMap1of1 "translate")
  [ReadsFile]

--------------
-- concat_* --
--------------

-- TODO separate concat module? or maybe this goes in ListLike?

mkConcat :: Type -> Function
mkConcat cType = newFnA1
  ("concat_" ++ ext cType)
  (Exactly $ ListOf cType)
  (Exactly cType)
  (aConcat cType)
  []

mkConcatEach :: Type -> Function
mkConcatEach cType = newFnA1
  ("concat_" ++ ext cType ++ "_each")
  (Exactly $ ListOf $ ListOf cType)
  (Exactly $ ListOf cType)
  (newMap1of1 $ "concat_" ++ ext cType)
  []

{- This is just a fancy `cat`, with handling for a couple cases:
 - * some args are empty and their <<emptywhatever>> should be removed
 - * all args are empty and they should be collapsed to one <<emptywhatever>>
 -
 - TODO special case of error handling here, since cat errors are usually temporary?
 -}
aConcat :: Type -> NewAction1
aConcat cType (ExprPath outPath') inList' = do
  -- This is all so we can get an example <<emptywhatever>> to cat.py
  -- ... there's gotta be a simpler way right?
  cfg <- fmap fromJust getShakeExtra
  let tmpDir'   = tmpdir cfg </> "cache" </> "concat"
      emptyPath = tmpDir' </> ("empty" ++ ext cType) <.> "txt"
      emptyStr  = "<<empty" ++ ext cType ++ ">>"
      loc = "ortholang.modules.seqio.aConcat"
      outPath = toPath loc cfg outPath'
      inList    = toPath loc cfg inList'
      inList''  = tmpDir' </> digest loc inList <.> "txt" -- TODO is that right?
  liftIO $ createDirectoryIfMissing True tmpDir'
  liftIO $ createDirectoryIfMissing True $ takeDirectory outPath'
  writeCachedLines loc emptyPath [emptyStr]
  inPaths <- readPaths loc inList'
  let inPaths' = map (fromPath loc cfg) inPaths
  need' loc inPaths'
  writeCachedLines loc inList'' inPaths'
  aSimpleScriptNoFix "cat.py" [ outPath, inList, toPath loc cfg emptyPath]

------------------------
-- split_fasta(_each) --
------------------------

splitFasta :: Type -> Function
splitFasta faType =
  let name = "split_" ++ ext faType
  in newFnA1
       name
       (Exactly faType)
       (Exactly $ ListOf faType)
       (aSplit name $ ext faType)
       []

splitFastaEach :: Type -> Function
splitFastaEach faType =
  let n2 = "split_" ++ ext faType
      n1 = n2 ++ "_each"
  in newFnA1
       n1
       (Exactly $ ListOf faType)
       (Exactly $ ListOf $ ListOf faType)
       (newMap1of1 n2)
       []

aSplit :: String -> String -> NewAction1
aSplit name e (ExprPath outPath') faPath' = do
  cfg <- fmap fromJust getShakeExtra
  -- let faPath'   = fromPath loc cfg faPath
  let loc = "ortholang.modules.seqio.aSplit"
      exprDir'  = tmpdir cfg </> "exprs"
      tmpDir'   = tmpdir cfg </> "cache" </> name -- TODO is there a fn for this?
      faPath    = toPath loc cfg faPath'
      prefix'   = tmpDir' </> digest loc faPath ++ "/"
      outDir'   = exprDir' </> "load_" ++ e
      -- outPath'  = fromPath loc cfg outPath
      outPath'' = traceA loc outPath' [outPath', faPath']
      tmpList   = tmpDir' </> takeFileName outPath' <.> "tmp"
      args      = [tmpList, outDir', prefix', faPath', e]
  -- TODO make sure stderr doesn't come through?
  -- TODO any locking needed here?
  liftIO $ createDirectoryIfMissing True tmpDir'
  liftIO $ createDirectoryIfMissing True outDir'
  -- TODO rewrite with runCmd -> tmpfile, then correct paths afterward in haskell
  -- out <- wrappedCmdOut False True cfg ref [faPath'] [] [] "split_fasta.py" args
  -- TODO why does this work when loaders are called one at a time, but not as part of a big script?
  -- TODO the IDs are always written properly, so why not the sequences??
  -- withWriteLock' tmpDir' $ do -- why is this required?
  runCmd $ CmdDesc
    { cmdBinary = "split_fasta.py"
    , cmdArguments = args
    , cmdFixEmpties = False -- TODO will be done in the next step right?
    , cmdParallel = True -- TODO make it parallel again?
    , cmdOptions = []
    , cmdInPatterns = [faPath']
    , cmdNoNeedDirs = []
    , cmdOutPath = tmpList
    , cmdExtraOutPaths = []
    , cmdSanitizePaths = [tmpList]
    , cmdExitCode = ExitSuccess
    , cmdRmPatterns = [outPath'', tmpList] -- TODO any more?
    }
  -- loadPaths <- readPaths tmpList
  -- when (null loadPaths) $ error $ "no fasta file written: " ++ tmpList
  -- writePaths outPath'' loadPaths
  writeCachedVersion loc outPath'' tmpList
