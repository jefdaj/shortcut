module OrthoLang.Modules.Busco
  where

-- TODO update to BUSCO v4.0.0
-- TODO add old datasets? maybe no need

import Development.Shake
import OrthoLang.Core.Types
import OrthoLang.Core.Paths (cacheDir, toOrthoLangPath, fromOrthoLangPath, exprPath)
import OrthoLang.Core.Actions (traceA, writeLits, runCmd, CmdDesc(..), readLit, readPaths, writePaths,
                              readFileStrict', symlink, readFileStrict, sanitizeFileInPlace)
import OrthoLang.Core.Compile.Basic (defaultTypeCheck, rExpr, mkLoad, rSimple,
                                    rSimpleScript, curl)
import OrthoLang.Core.Compile.Map   (rMap, rMapSimpleScript)
import OrthoLang.Modules.SeqIO (fna, faa, mkConcat)
import OrthoLang.Modules.BlastDB (aFilterList)
import System.FilePath (takeBaseName, takeDirectory, (<.>), (</>))
import System.Directory           (createDirectoryIfMissing)
import OrthoLang.Core.Util         (resolveSymlinks, unlessExists, headOrDie)
import System.Exit (ExitCode(..))
import System.FilePath.Glob       (glob)
import Data.Scientific -- (formatScientific, FPFormat(..))
import Control.Monad (when)
import Data.List ((\\))
import Data.Maybe (isJust)

orthoLangModule :: OrthoLangModule
orthoLangModule = OrthoLangModule
  { mName = "Busco"
  , mDesc = "Benchmarking Universal Single-Copy Orthologs"
  , mTypes = [blh, bsr, bst, faa]
  , mFunctions =
      [ loadLineage
      , buscoListLineages
      , buscoFetchLineage
      , buscoProteins       , buscoProteinsEach
      , buscoTranscriptome  , buscoTranscriptomeEach
      , buscoPercentComplete, buscoPercentCompleteEach
      , buscoScoresTable
      , buscoFilterCompleteness
      , mkConcat bst -- TODO Each too?
      ]
  }

blh :: OrthoLangType
blh = OrthoLangType
  { tExt  = "blh"
  , tDesc = "BUSCO lineage HMMs"
  , tShow = defaultShowN 6
  }

bsr :: OrthoLangType
bsr = OrthoLangType
  { tExt  = "bsr"
  , tDesc = "BUSCO results"
  , tShow = \_ ref path -> do
      txt <- readFileStrict ref path
      let tail9 = unlines . filter (not . null) . reverse . take 9 . reverse . lines
      return $ init $ "BUSCO result:" ++ tail9 txt
  }

bst :: OrthoLangType
bst = OrthoLangType
  { tExt  = "bst"
  , tDesc = "BUSCO scores table"
  , tShow = defaultShow
  }

loadLineage :: OrthoLangFunction
loadLineage = mkLoad False "load_lineage" blh

buscoCache :: OrthoLangConfig -> OrthoLangPath
buscoCache cfg = cacheDir cfg "busco"

-------------------------
-- busco_list_lineages --
-------------------------

buscoListLineages :: OrthoLangFunction
buscoListLineages = OrthoLangFunction
  { fNames     = [name]
  , fTypeCheck = defaultTypeCheck [str] (ListOf str)
  , fTypeDesc  = mkTypeDesc name  [str] (ListOf str)
  , fFixity    = Prefix
  , fRules     = rBuscoListLineages
  }
  where
    name = "busco_list_lineages"

rBuscoListLineages :: RulesFn
rBuscoListLineages s@(_, cfg, ref, ids) e@(OrthoLangFun _ _ _ _ [f]) = do
  (ExprPath fPath) <- rExpr s f
  let fPath' = toOrthoLangPath   cfg fPath
  listTmp %> \_ -> aBuscoListLineages   cfg ref ids lTmp'
  oPath'  %> \_ -> aFilterList cfg ref ids oPath lTmp' fPath'
  return (ExprPath oPath')
  where
    oPath   = exprPath s e
    tmpDir  = buscoCache cfg
    tmpDir' = fromOrthoLangPath cfg tmpDir
    listTmp = tmpDir' </> "dblist" <.> "txt"
    oPath'  = fromOrthoLangPath cfg oPath
    lTmp'   = toOrthoLangPath   cfg listTmp
rBuscoListLineages _ _ = fail "bad argument to rBuscoListLineages"

aBuscoListLineages :: OrthoLangConfig -> Locks -> HashedIDsRef -> OrthoLangPath -> Action ()
aBuscoListLineages cfg ref _ listTmp = do
  liftIO $ createDirectoryIfMissing True tmpDir
  writeLits cfg ref oPath allLineages
  where
    listTmp' = fromOrthoLangPath cfg listTmp
    tmpDir   = takeDirectory $ listTmp'
    oPath    = traceA "aBuscoListLineages" listTmp' [listTmp']
    -- These seem static, but may have to be updated later.
    -- The list is generated by "Download all datasets" on the homepage
    allLineages =
      -- Bacteria
      [ "v2/datasets/bacteria_odb9"
      , "v2/datasets/proteobacteria_odb9"
      , "v2/datasets/rhizobiales_odb9"
      , "v2/datasets/betaproteobacteria_odb9"
      , "v2/datasets/gammaproteobacteria_odb9"
      , "v2/datasets/enterobacteriales_odb9"
      , "v2/datasets/deltaepsilonsub_odb9"
      , "v2/datasets/actinobacteria_odb9"
      , "v2/datasets/cyanobacteria_odb9"
      , "v2/datasets/firmicutes_odb9"
      , "v2/datasets/clostridia_odb9"
      , "v2/datasets/lactobacillales_odb9"
      , "v2/datasets/bacillales_odb9"
      , "v2/datasets/bacteroidetes_odb9"
      , "v2/datasets/spirochaetes_odb9"
      , "v2/datasets/tenericutes_odb9"
      -- Eukaryota
      , "v2/datasets/eukaryota_odb9"
      , "v2/datasets/fungi_odb9"
      , "v2/datasets/microsporidia_odb9"
      , "v2/datasets/dikarya_odb9"
      , "v2/datasets/ascomycota_odb9"
      , "v2/datasets/pezizomycotina_odb9"
      , "v2/datasets/eurotiomycetes_odb9"
      , "v2/datasets/sordariomyceta_odb9"
      , "v2/datasets/saccharomyceta_odb9"
      , "v2/datasets/saccharomycetales_odb9"
      , "v2/datasets/basidiomycota_odb9"
      , "v2/datasets/metazoa_odb9"
      , "v2/datasets/nematoda_odb9"
      , "v2/datasets/arthropoda_odb9"
      , "v2/datasets/insecta_odb9"
      , "v2/datasets/endopterygota_odb9"
      , "v2/datasets/hymenoptera_odb9"
      , "v2/datasets/diptera_odb9"
      , "v2/datasets/vertebrata_odb9"
      , "v2/datasets/actinopterygii_odb9"
      , "v2/datasets/tetrapoda_odb9"
      , "v2/datasets/aves_odb9"
      , "v2/datasets/mammalia_odb9"
      , "v2/datasets/euarchontoglires_odb9"
      , "v2/datasets/laurasiatheria_odb9"
      , "v2/datasets/embryophyta_odb9"
      , "v2/datasets/protists_ensembl"
      , "v2/datasets/alveolata_stramenophiles_ensembl"
      -- prerelease
      , "datasets/prerelease/chlorophyta_odb10"
      , "datasets/prerelease/embryophyta_odb10"
      , "datasets/prerelease/eudicotyledons_odb10"
      , "datasets/prerelease/liliopsida_odb10"
      , "datasets/prerelease/solanaceae_odb10"
      , "datasets/prerelease/viridiplantae_odb10"

      ]

------------------------
-- busco_fetch_lineage --
------------------------

-- TODO consistent naming with similar functions
-- TODO busco_fetch_lineages? (the _each version)

buscoFetchLineage :: OrthoLangFunction
buscoFetchLineage  = OrthoLangFunction
  { fNames     = [name]
  , fTypeCheck = defaultTypeCheck [str] blh
  , fTypeDesc  = mkTypeDesc name  [str] blh
  , fFixity    = Prefix
  , fRules     = rBuscoFetchLineage
  }
  where
    name = "busco_fetch_lineage"

-- TODO move to Util?
untar :: OrthoLangConfig -> Locks -> OrthoLangPath -> OrthoLangPath -> Action ()
untar cfg ref from to = runCmd cfg ref $ CmdDesc
  { cmdBinary = "tar"
  , cmdArguments = (if isJust (cfgDebug cfg) then "-v" else ""):["-xf", from', "-C", takeDirectory to']
  , cmdFixEmpties = False
  , cmdParallel   = False
  , cmdInPatterns = [from']
  , cmdOutPath    = to'
  , cmdExtraOutPaths = []
  , cmdSanitizePaths = []
  , cmdOptions = []
  , cmdExitCode = ExitSuccess
  , cmdRmPatterns = [to']
  }
  where
    from' = fromOrthoLangPath cfg from
    to' = fromOrthoLangPath cfg to

rBuscoFetchLineage :: RulesFn
rBuscoFetchLineage st@(_, cfg, ref, _) expr@(OrthoLangFun _ _ _ _ [nPath]) = do
  (ExprPath namePath) <- rExpr st nPath
  let outPath  = exprPath st expr
      outPath' = fromOrthoLangPath cfg outPath
      blhDir   = (fromOrthoLangPath cfg $ buscoCache cfg) </> "lineages"
  outPath' %> \_ -> do
    nameStr <- readLit cfg ref namePath
    let untarPath = blhDir </> nameStr
        url       = "http://busco.ezlab.org/" ++ nameStr ++ ".tar.gz"
        datasetPath'  = untarPath </> "dataset.cfg" -- final output we link to
        datasetPath   = toOrthoLangPath cfg datasetPath'
    tarPath <- fmap (fromOrthoLangPath cfg) $ curl cfg ref url
    unlessExists untarPath $ do
      untar cfg ref (toOrthoLangPath cfg tarPath) (toOrthoLangPath cfg untarPath)
    symlink cfg ref outPath datasetPath
  return $ ExprPath outPath'
rBuscoFetchLineage _ e = error $ "bad argument to rBuscoFetchLineage: " ++ show e

-------------------------------------------
-- busco_{genome,proteins,transcriptome} --
-------------------------------------------

mkBusco :: String -> String -> OrthoLangType -> OrthoLangFunction
mkBusco name mode inType = OrthoLangFunction
  { fNames     = [name]
  , fTypeCheck = defaultTypeCheck [blh, inType] bsr
  , fTypeDesc  = mkTypeDesc name  [blh, inType] bsr
  , fFixity    = Prefix
  , fRules     = rSimple $ aBusco mode
  }

buscoProteins, buscoTranscriptome :: OrthoLangFunction
buscoProteins      = mkBusco "busco_proteins"      "prot" faa
buscoTranscriptome = mkBusco "busco_transcriptome" "tran" fna
-- buscoGenome = mkBusco "busco_genome" "geno"

aBusco :: String -> (OrthoLangConfig -> Locks -> HashedIDsRef -> [OrthoLangPath] -> Action ())
aBusco mode cfg ref _ [outPath, blhPath, faaPath] = do
  let out' = fromOrthoLangPath cfg outPath
      blh' = takeDirectory $ fromOrthoLangPath cfg blhPath
      cDir = fromOrthoLangPath cfg $ buscoCache cfg
      rDir = cDir </> "runs"
      faa' = fromOrthoLangPath cfg faaPath
  blh'' <- liftIO $ resolveSymlinks (Just $ cfgTmpDir cfg) blh'
  liftIO $ createDirectoryIfMissing True rDir
  runCmd cfg ref $ CmdDesc
    { cmdBinary = "busco.sh"
    , cmdArguments = [out', faa', blh'', mode, cDir] -- TODO cfgtemplate, tdir
    , cmdFixEmpties = False
    , cmdParallel = False -- TODO fix shake error and set to True
    , cmdInPatterns = [faa']
    , cmdOutPath = out'
    , cmdExtraOutPaths = []
    , cmdSanitizePaths = []
    , cmdOptions = []
    , cmdExitCode = ExitSuccess
    , cmdRmPatterns = [out']
    }
  -- This is rediculous but I haven't been able to shorten it...
  let oBasePtn = "*" ++ takeBaseName out' ++ "*"
      tmpOutPtn = rDir </> oBasePtn </> "short_summary*.txt"
  tmpOut <- liftIO $ fmap (headOrDie "failed to read BUSCO summary in aBusco") $ glob tmpOutPtn
  sanitizeFileInPlace cfg ref tmpOut -- will this confuse shake?
  symlink cfg ref outPath $ toOrthoLangPath cfg tmpOut
aBusco _ _ _ _ as = error $ "bad argument to aBusco: " ++ show as

------------------------------------------------
-- busco_{genome,proteins,transcriptome}_each --
------------------------------------------------

mkBuscoEach :: String -> String -> OrthoLangType -> OrthoLangFunction
mkBuscoEach name mode inType = OrthoLangFunction
  { fNames     = [name]
  , fTypeCheck = defaultTypeCheck [blh, (ListOf inType)] (ListOf bsr)
  , fTypeDesc  = mkTypeDesc name  [blh, (ListOf inType)] (ListOf bsr)
  , fFixity    = Prefix
  , fRules     = rMap 2 $ aBusco mode
  }

buscoProteinsEach, buscoTranscriptomeEach :: OrthoLangFunction
buscoProteinsEach      = mkBuscoEach "busco_proteins_each"      "prot" faa
buscoTranscriptomeEach = mkBuscoEach "busco_transcriptome_each" "tran" fna
-- buscoGenomeEach = mkBusco "busco_genome_each" "geno"

-----------------------------
-- busco_percent_complete* --
-----------------------------

buscoPercentComplete :: OrthoLangFunction
buscoPercentComplete  = OrthoLangFunction
  { fNames     = [name]
  , fTypeCheck = defaultTypeCheck [bsr] num
  , fTypeDesc  = mkTypeDesc name  [bsr] num
  , fFixity    = Prefix
  , fRules     = rSimpleScript "busco_percent_complete.sh"
  }
  where
    name = "busco_percent_complete"

buscoPercentCompleteEach :: OrthoLangFunction
buscoPercentCompleteEach  = OrthoLangFunction
  { fNames     = [name]
  , fTypeCheck = defaultTypeCheck [ListOf bsr] (ListOf num)
  , fTypeDesc  = mkTypeDesc name  [ListOf bsr] (ListOf num)
  , fFixity    = Prefix
  , fRules     = rMapSimpleScript 1 "busco_percent_complete.sh"
  }
  where
    name = "busco_percent_complete_each"

------------------------
-- busco_scores_table --
------------------------

buscoScoresTable :: OrthoLangFunction
buscoScoresTable  = OrthoLangFunction
  { fNames     = [name]
  , fTypeCheck = defaultTypeCheck [ListOf bsr] bst
  , fTypeDesc  = mkTypeDesc name  [ListOf bsr] bst
  , fFixity    = Prefix
  -- , fRules     = rSimpleScript $ name <.> "py"
  , fRules     = rBuscoScoresTable
  }
  where
    name = "busco_scores_table"

-- TODO variant of rSimpleScript that reads + passes in a list of input files?
rBuscoScoresTable :: RulesFn
rBuscoScoresTable s@(_, cfg, ref, _) e@(OrthoLangFun _ _ _ _ [l]) = do
  (ExprPath lsPath) <- rExpr s l
  let o  = exprPath s e
      o' = fromOrthoLangPath cfg o
  o' %> \_ -> do
    ins <- readPaths cfg ref lsPath
    let ins' = map (fromOrthoLangPath cfg) ins
    runCmd cfg ref $ CmdDesc
      { cmdBinary = "busco_scores_table.py"
      , cmdArguments = o':ins'
      , cmdFixEmpties = False
      , cmdParallel   = False
      , cmdInPatterns = ins'
      , cmdOutPath    = o'
      , cmdExtraOutPaths = []
      , cmdSanitizePaths = [] -- TODO any?
      , cmdOptions = []
      , cmdExitCode = ExitSuccess
      , cmdRmPatterns = [o']
      }
  return $ ExprPath o'
rBuscoScoresTable _ e = error $ "bad argument to rBuscoScoresTable: " ++ show e

-------------------------------
-- busco_filter_completeness --
-------------------------------

-- TODO this can filter proteomes/transcriptomes by which their completeness in a table
--      bst should it take the table as an explicit arg, or generate it from the inputs?
--      explicit is probably better! abort with error if the table doesn't contain all of them
-- TODO remove busco_percent_complete* afterward since the table will be more useful?
-- TODO make an _each version of this one

buscoFilterCompleteness :: OrthoLangFunction
buscoFilterCompleteness  = OrthoLangFunction
  { fNames     = [name]
  , fTypeCheck = defaultTypeCheck [num, bst, ListOf faa] (ListOf faa) -- TODO or fna?
  , fTypeDesc  = mkTypeDesc name  [num, bst, ListOf faa] (ListOf faa) -- TODO or fna?
  , fFixity    = Prefix
  , fRules     = rBuscoFilterCompleteness
  }
  where
    name = "busco_filter_completeness"

-- TODO how to get the hash? resolveSymlinks and read it from the filename?
--      that might fail if it was generated by a fn instead of loaded from an external file
--      maybe the solution is to add generated fastas to cached lines?
-- TODO try the same way it works for sets: one canonical full path!
-- TODO do it the simple way for now, then see if it breaks and if so fix it
rBuscoFilterCompleteness :: RulesFn
rBuscoFilterCompleteness s@(_, cfg, ref, _) e@(OrthoLangFun _ _ _ _ [m, t, fs]) = do
  (ExprPath scorePath) <- rExpr s m
  (ExprPath tablePath) <- rExpr s t
  (ExprPath faasList ) <- rExpr s fs
  let out  = exprPath s e
      out' = fromOrthoLangPath cfg out
  out' %> \_ -> do
    score <- fmap (read :: String -> Scientific) $ readLit  cfg ref scorePath
    table <- readFileStrict' cfg ref tablePath -- TODO best read fn?
    faaPaths <- readPaths cfg ref faasList
    let allScores = map parseWords $ map words $ lines table
        missing   = faaPaths \\ map fst allScores
        okPaths   = map fst $ filter (\(_, c) -> c >= score) allScores
    when (not $ null missing) $
      error $ "these paths are missing from the table: " ++ show missing
    writePaths cfg ref out' okPaths
  return $ ExprPath out'
  where
    parseWords (p:c:_) = (OrthoLangPath p, read c :: Scientific)
    parseWords ws = error $ "bad argument to parseWords: " ++ show ws
rBuscoFilterCompleteness _ e = error $
  "bad argument to rBuscoFilterCompleteness: " ++ show e
