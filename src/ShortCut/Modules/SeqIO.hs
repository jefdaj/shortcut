-- TODO rename something more general like SeqUtils

module ShortCut.Modules.SeqIO where

import Development.Shake
import ShortCut.Core.Types

import ShortCut.Core.Config (wrappedCmd)
import ShortCut.Core.Debug  (debug, debugReadLines, debugTrackWrite, debugAction)
import ShortCut.Core.Compile.Paths  (exprPath, cacheDir)
import ShortCut.Core.Compile.Rules  (rExpr, defaultTypeCheck, rLoadOne, rLoadList,
                             rOneArgScript, rOneArgListScript)
import System.FilePath      ((</>))

cutModule :: CutModule
cutModule = CutModule
  { mName = "seqio"
  , mFunctions =
    [ loadGbk
    , loadGbkEach
    , loadFaa
    , loadFaaEach
    , loadFna
    , loadFnaEach
    , gbkToFaa -- TODO each?
    , gbkToFna -- TODO each?
    , extractSeqs
    , extractSeqIDs
    , translate
    , concatFastas
    -- TODO combo that loads multiple fnas or faas and concats them?
    -- TODO combo that loads multiple gbks -> fna or faa?
    ]
  }

-- load a single file --

{- Takes a string with the filepath to load. Creates a trivial expression file
 - that's just a symlink to the given path. These should be the only absolute
 - links, and the only ones that point outside the temp dir.
 - TODO still true?
 -}
mkLoad :: String -> CutType -> CutFunction
mkLoad name rtn = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [str] rtn
  , fFixity    = Prefix
  , fRules  = rLoadOne rtn
  }

-- load a list of files --

{- Like cLoad, except it operates on a list of strings. Note that you can also
 - load lists using cLoad, but it's not recommended because then you have to
 - write the list in a file, whereas this can handle literal lists in the
 - source code.
 -}

-- TODO fix it putting both the initial files and lists of them in the same dir!
--      (.faa and .faa.list are together in exprs/load_faa_each,
--       when the former should be in exprs/load_faa)
mkLoadList :: String -> CutType -> CutFunction
mkLoadList name rtn = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [(SetOf str)] (SetOf rtn)
  , fFixity    = Prefix
  , fRules  = rLoadList
  }

gbk :: CutType
gbk = CutType
  { tExt  = "gbk"
  , tDesc = "genbank file"
  , tShow  = defaultShow
  }

faa :: CutType
faa = CutType
  { tExt  = "faa"
  , tDesc = "FASTA (amino acid)"
  , tShow  = defaultShow
  }

fna :: CutType
fna = CutType
  { tExt  = "fna"
  , tDesc = "FASTA (nucleic acid)"
  , tShow  = defaultShow
  }

gbkToFaa :: CutFunction
gbkToFaa = CutFunction
  { fName      = "gbk_to_faa"
  , fTypeCheck = defaultTypeCheck [gbk] faa
  , fFixity    = Prefix
  , fRules  = rOneArgScript "seqio" "gbk_to_faa.py"
  }

gbkToFna :: CutFunction
gbkToFna = CutFunction
  { fName      = "gbk_to_fna"
  , fTypeCheck = defaultTypeCheck [gbk] fna
  , fFixity    = Prefix
  , fRules  = rOneArgScript "seqio" "gbk_to_fna.py"
  }

--------------------
-- load sequences --
--------------------

loadFaa :: CutFunction
loadFaa = mkLoad "load_faa" faa

loadFaaEach :: CutFunction
loadFaaEach = mkLoadList "load_faa_each" faa

loadFna :: CutFunction
loadFna = mkLoad "load_fna" fna

loadFnaEach :: CutFunction
loadFnaEach = mkLoadList "load_fna_each" fna

loadGbk :: CutFunction
loadGbk = mkLoad "load_gbk" gbk

loadGbkEach :: CutFunction
loadGbkEach = mkLoadList "load_gbk_each" gbk

-------------------------------------------
-- extract sequence IDs from FASTA files --
-------------------------------------------

-- TODO this needs to do relative paths again, not absolute!
-- TODO also extract them from genbank files

extractSeqIDs :: CutFunction
extractSeqIDs = CutFunction
  { fName      = "extract_ids"
  , fFixity    = Prefix
  , fTypeCheck = tExtractSeqIDs
  , fRules  = rExtractSeqIDs
  }

tExtractSeqIDs :: [CutType] -> Either String CutType
tExtractSeqIDs [x] | elem x [faa, fna] = Right (SetOf str)
tExtractSeqIDs _ = Left "expected a fasta file"

-- TODO these should put their tmpfiles in cache/extract_ids!
rExtractSeqIDs :: CutState -> CutExpr -> Rules ExprPath
rExtractSeqIDs = rOneArgListScript "seqio" "extract_ids.py"

----------------------------------------------
-- extract sequences from FASTA files by ID --
----------------------------------------------

-- TODO also extract them from genbank files

extractSeqs :: CutFunction
extractSeqs = CutFunction
  { fName      = "extract_seqs"
  , fFixity    = Prefix
  , fTypeCheck = tExtractSeqs
  , fRules  = rExtractSeqs
  }

-- TODO does SetOf str match on the value or just the constructor?
tExtractSeqs  :: [CutType] -> Either String CutType
tExtractSeqs [x, SetOf s] | s == str && elem x [faa, fna] = Right x
tExtractSeqs _ = Left "expected a list of strings and a fasta file"

-- TODO can this be replaced with rOneArgListScript?
rExtractSeqs :: CutState -> CutExpr -> Rules ExprPath
rExtractSeqs s@(_,cfg) e@(CutFun _ _ _ _ [fa, ids]) = do
  (ExprPath faPath ) <- rExpr s fa
  (ExprPath idsPath) <- rExpr s ids
  -- liftIO . putStrLn $ "extracting sequences from " ++ faPath
  let (CacheDir tmpDir ) = cacheDir cfg "seqio"
      (ExprPath outPath) = exprPath cfg True e []
      -- tmpList = cacheFile cfg "seqio" ids "txt"
  -- TODO remove extra tmpdir here if possible, and put file somewhere standard
  -- tmpList %> \_ -> do
  outPath %> \_ -> aExtractSeqs cfg outPath tmpDir faPath idsPath 
  return (ExprPath outPath)
rExtractSeqs _ _ = error "bad argument to extractSeqs"

aExtractSeqs :: CutConfig -> String -> FilePath -> FilePath -> FilePath -> Action ()
aExtractSeqs cfg outPath tmpDir faPath idsPath = do
  -- liftIO $ createDirectoryIfMissing True tmpDir -- TODO put in fromShortCutSet?
  -- fromShortCutSet cfg idsPath (ExprPath tmpList)
-- outPath %> \_ -> do
  -- need [faPath, tmpList]
  -- liftIO $ createDirectoryIfMissing True tmpDir
  need [faPath, idsPath]
  quietly $ wrappedCmd cfg [outPath] [Cwd tmpDir]
                       "extract_seqs.py" [outPath, faPath, idsPath]
  let out = debugAction cfg "aExtractSeqs" outPath [outPath, tmpDir, faPath, idsPath]
  debugTrackWrite cfg [out]

-------------------------------------
-- convert between DNA and protein --
-------------------------------------

-- TODO name something else like fna_to_faa?
translate :: CutFunction
translate = CutFunction
  { fName      = "translate"
  , fFixity    = Prefix
  , fTypeCheck = defaultTypeCheck [fna] faa
  , fRules  = rConvert "translate.py"
  }

-- TODO remove as biologically invalid?
-- back_transcribe :: CutFunction
-- back_transcribe = CutFunction
--   { fName      = "back_transcribe"
--   , fFixity    = Prefix
--   , fTypeCheck = defaultTypeCheck [faa] fna
--   , fRules  = rConvert "back_transcribe.py"
--   }

-- TODO can this use rOneArgScript?
rConvert :: FilePath -> CutState -> CutExpr -> Rules ExprPath
rConvert script s@(_,cfg) e@(CutFun _ _ _ _ [fa]) = do
  (ExprPath faPath) <- rExpr s fa
  let (ExprPath oPath) = exprPath cfg True e []
  oPath %> \_ -> aConvert cfg oPath script faPath
  return (ExprPath oPath)
rConvert _ _ _ = error "bad argument to rConvert"

aConvert :: CutConfig -> FilePath -> FilePath -> FilePath -> Action ()
aConvert cfg oPath script faPath = do
  need [faPath]
  unit $ wrappedCmd cfg [oPath] [] script [oPath, faPath]
  let oPath' = debugAction cfg "aConvert" oPath [oPath, script, faPath]
  debugTrackWrite cfg [oPath'] -- TODO is this implied?

------------------------
-- concat fasta files --
------------------------

concatFastas :: CutFunction
concatFastas = CutFunction
  { fName      = "concat_fastas"
  , fFixity    = Prefix
  , fTypeCheck = tConcatFastas
  , fRules  = rConcat
  }

tConcatFastas :: [CutType] -> Either String CutType
tConcatFastas [SetOf x] | elem x [faa, fna] = Right x
tConcatFastas _ = Left "expected a list of fasta files (of the same type)"

rConcat :: CutState -> CutExpr -> Rules ExprPath
rConcat s@(_,cfg) e@(CutFun _ _ _ _ [fs]) = do
  (ExprPath fsPath) <- rExpr s fs
  let (ExprPath oPath) = exprPath cfg True e []
  oPath %> \_ -> aConcat cfg oPath fsPath
  return (ExprPath oPath)
rConcat _ _ = error "bad argument to rConcat"

aConcat :: CutConfig -> String -> [Char] -> Action ()
aConcat cfg oPath fsPath = do
  faPaths <- fmap (map (cfgTmpDir cfg </>)) -- TODO utility fn for this!
             (debugReadLines cfg (debug cfg ("fsPath: " ++ fsPath)
                                  fsPath))
  need (debug cfg ("faPaths: " ++ show faPaths) faPaths)
  let catArgs = faPaths ++ [">", oPath]
      oPath'  = debugAction cfg "aConcat" oPath [oPath, fsPath]
  unit $ quietly $ wrappedCmd cfg [oPath] [Shell] "cat"
                     (debug cfg ("catArgs: " ++ show catArgs) catArgs)
  debugTrackWrite cfg [oPath']
