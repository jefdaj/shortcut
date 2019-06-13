module ShortCut.Modules.Busco
  where

import Development.Shake
import ShortCut.Core.Types
import ShortCut.Core.Paths (cacheDir, toCutPath, fromCutPath, exprPath)
import ShortCut.Core.Actions (debugA, writeLits, runCmd, CmdDesc(..), readLit,
                              symlink, readFileStrict, sanitizeFileInPlace)
import ShortCut.Core.Compile.Basic (defaultTypeCheck, rExpr, mkLoad, rSimple,
                                    rSimpleScript, curl)
import ShortCut.Core.Compile.Map   (rMap, rMapSimpleScript)
import ShortCut.Modules.SeqIO (fna, faa)
import ShortCut.Modules.BlastDB (aFilterList)
import System.FilePath (takeBaseName, takeDirectory, (<.>), (</>))
import System.Directory           (createDirectoryIfMissing)
import ShortCut.Core.Util         (resolveSymlinks, unlessExists)
import System.Exit (ExitCode(..))
import System.FilePath.Glob       (glob)

cutModule :: CutModule
cutModule = CutModule
  { mName = "Busco"
  , mDesc = "Benchmarking Universal Single-Copy Orthologs"
  , mTypes = [bul, bur, but, faa]
  , mFunctions =
      [ loadLineage
      , buscoListLineages
      , buscoFetchLineage
      , buscoProteins       , buscoProteinsEach
      , buscoTranscriptome  , buscoTranscriptomeEach
      , buscoPercentComplete, buscoPercentCompleteEach
      , buscoScoresTable
      , buscoFilterProteins
      ]
  }

bul :: CutType
bul = CutType
  { tExt  = "bul"
  , tDesc = "BUSCO lineage HMMs"
  , tShow = defaultShowN 6
  }

bur :: CutType
bur = CutType
  { tExt  = "bur"
  , tDesc = "BUSCO results"
  , tShow = \_ ref path -> do
      txt <- readFileStrict ref path
      let tail9 = unlines . filter (not . null) . reverse . take 9 . reverse . lines
      return $ init $ "BUSCO result:" ++ tail9 txt
  }

but :: CutType
but = CutType
  { tExt  = "but"
  , tDesc = "BUSCO scores table"
  , tShow = defaultShow
  }

loadLineage :: CutFunction
loadLineage = mkLoad False "load_lineage" bul

buscoCache :: CutConfig -> CutPath
buscoCache cfg = cacheDir cfg "busco"

-------------------------
-- busco_list_lineages --
-------------------------

buscoListLineages :: CutFunction
buscoListLineages = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [str] (ListOf str)
  , fTypeDesc  = mkTypeDesc name  [str] (ListOf str)
  , fDesc      = Nothing
  , fFixity    = Prefix
  , fRules     = rBuscoListLineages
  }
  where
    name = "busco_list_lineages"

rBuscoListLineages :: RulesFn
rBuscoListLineages s@(_, cfg, ref, ids) e@(CutFun _ _ _ _ [f]) = do
  (ExprPath fPath) <- rExpr s f
  let fPath' = toCutPath   cfg fPath
  listTmp %> \_ -> aBuscoListLineages   cfg ref ids lTmp'
  oPath'  %> \_ -> aFilterList cfg ref ids oPath lTmp' fPath'
  return (ExprPath oPath')
  where
    oPath   = exprPath s e
    tmpDir  = buscoCache cfg
    tmpDir' = fromCutPath cfg tmpDir
    listTmp = tmpDir' </> "dblist" <.> "txt"
    oPath'  = fromCutPath cfg oPath
    lTmp'   = toCutPath   cfg listTmp
rBuscoListLineages _ _ = fail "bad argument to rBuscoListLineages"

aBuscoListLineages :: CutConfig -> Locks -> HashedSeqIDsRef -> CutPath -> Action ()
aBuscoListLineages cfg ref _ listTmp = do
  liftIO $ createDirectoryIfMissing True tmpDir
  writeLits cfg ref oPath allLineages
  where
    listTmp' = fromCutPath cfg listTmp
    tmpDir   = takeDirectory $ listTmp'
    oPath    = debugA cfg "aBuscoListLineages" listTmp' [listTmp']
    -- These seem static, but may have to be updated later.
    -- The list is generated by "Download all datasets" on the homepage
    allLineages =
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

buscoFetchLineage :: CutFunction
buscoFetchLineage  = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [str] bul
  , fTypeDesc  = mkTypeDesc name  [str] bul
  , fDesc      = Nothing
  , fFixity    = Prefix
  , fRules     = rBuscoFetchLineage
  }
  where
    name = "busco_fetch_lineage"

-- TODO move to Util?
untar :: CutConfig -> Locks -> CutPath -> CutPath -> Action ()
untar cfg ref from to = runCmd cfg ref $ CmdDesc
  { cmdBinary = "tar"
  , cmdArguments = (if cfgDebug cfg then "-v" else ""):["-xf", from', "-C", takeDirectory to']
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
    from' = fromCutPath cfg from
    to' = fromCutPath cfg to

rBuscoFetchLineage :: RulesFn
rBuscoFetchLineage st@(_, cfg, ref, _) expr@(CutFun _ _ _ _ [nPath]) = do
  (ExprPath namePath) <- rExpr st nPath
  let outPath  = exprPath st expr
      outPath' = fromCutPath cfg outPath
      bulDir   = (fromCutPath cfg $ buscoCache cfg) </> "lineages"
  outPath' %> \_ -> do
    nameStr <- readLit cfg ref namePath
    let untarPath = bulDir </> nameStr
        url       = "http://busco.ezlab.org/" ++ nameStr ++ ".tar.gz"
        datasetPath'  = untarPath </> "dataset.cfg" -- final output we link to
        datasetPath   = toCutPath cfg datasetPath'
    tarPath <- fmap (fromCutPath cfg) $ curl cfg ref url
    unlessExists untarPath $ do
      untar cfg ref (toCutPath cfg tarPath) (toCutPath cfg untarPath)
    symlink cfg ref outPath datasetPath
  return $ ExprPath outPath'
rBuscoFetchLineage _ e = error $ "bad argument to rBuscoFetchLineage: " ++ show e

-------------------------------------------
-- busco_{genome,proteins,transcriptome} --
-------------------------------------------

mkBusco :: String -> String -> CutType -> CutFunction
mkBusco name mode inType = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [bul, inType] bur
  , fTypeDesc  = mkTypeDesc name  [bul, inType] bur
  , fDesc      = Nothing
  , fFixity    = Prefix
  , fRules     = rSimple $ aBusco mode
  }

buscoProteins, buscoTranscriptome :: CutFunction
buscoProteins      = mkBusco "busco_proteins"      "prot" faa
buscoTranscriptome = mkBusco "busco_transcriptome" "tran" fna
-- buscoGenome = mkBusco "busco_genome" "geno"

aBusco :: String -> (CutConfig -> Locks -> HashedSeqIDsRef -> [CutPath] -> Action ())
aBusco mode cfg ref _ [outPath, bulPath, faaPath] = do
  let out' = fromCutPath cfg outPath
      bul' = takeDirectory $ fromCutPath cfg bulPath
      cDir = fromCutPath cfg $ buscoCache cfg
      rDir = cDir </> "runs"
      faa' = fromCutPath cfg faaPath
  bul'' <- liftIO $ resolveSymlinks (Just $ cfgTmpDir cfg) bul'
  liftIO $ createDirectoryIfMissing True rDir
  runCmd cfg ref $ CmdDesc
    { cmdBinary = "busco.sh"
    , cmdArguments = [out', faa', bul'', mode, cDir] -- TODO cfgtemplate, tdir
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
  tmpOut <- liftIO $ fmap head $ glob tmpOutPtn
  sanitizeFileInPlace cfg ref tmpOut -- will this confuse shake?
  symlink cfg ref outPath $ toCutPath cfg tmpOut
aBusco _ _ _ _ as = error $ "bad argument to aBusco: " ++ show as

------------------------------------------------
-- busco_{genome,proteins,transcriptome}_each --
------------------------------------------------

mkBuscoEach :: String -> String -> CutType -> CutFunction
mkBuscoEach name mode inType = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [bul, (ListOf inType)] (ListOf bur)
  , fTypeDesc  = mkTypeDesc name  [bul, (ListOf inType)] (ListOf bur)
  , fDesc      = Nothing
  , fFixity    = Prefix
  , fRules     = rMap 2 $ aBusco mode
  }

buscoProteinsEach, buscoTranscriptomeEach :: CutFunction
buscoProteinsEach      = mkBuscoEach "busco_proteins_each"      "prot" faa
buscoTranscriptomeEach = mkBuscoEach "busco_transcriptome_each" "tran" fna
-- buscoGenomeEach = mkBusco "busco_genome_each" "geno"

-----------------------------
-- busco_percent_complete* --
-----------------------------

buscoPercentComplete :: CutFunction
buscoPercentComplete  = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [bur] num
  , fTypeDesc  = mkTypeDesc name  [bur] num
  , fDesc      = Nothing
  , fFixity    = Prefix
  , fRules     = rSimpleScript "busco_percent_complete.sh"
  }
  where
    name = "busco_percent_complete"

buscoPercentCompleteEach :: CutFunction
buscoPercentCompleteEach  = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [ListOf bur] (ListOf num)
  , fTypeDesc  = mkTypeDesc name  [ListOf bur] (ListOf num)
  , fDesc      = Nothing
  , fFixity    = Prefix
  , fRules     = rMapSimpleScript 1 "busco_percent_complete.sh"
  }
  where
    name = "busco_percent_complete_each"

------------------------
-- busco_scores_table --
------------------------

buscoScoresTable :: CutFunction
buscoScoresTable  = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [ListOf bur] but
  , fTypeDesc  = mkTypeDesc name  [ListOf bur] but
  , fDesc      = Nothing
  , fFixity    = Prefix
  , fRules     = rSimpleScript $ name <.> "py"
  }
  where
    name = "busco_scores_table"

-------------------------------
-- busco_filter_completeness --
-------------------------------

-- TODO write something that goes from bur.list -> scores table
-- TODO then this can filter the scores table by completeness, simple
-- TODO remove busco_percent_complete* afterward since the table will be more useful?

buscoFilterProteins :: CutFunction
buscoFilterProteins  = CutFunction
  { fName      = name
  , fTypeCheck = defaultTypeCheck [bul, num, ListOf faa] (ListOf faa)
  , fTypeDesc  = mkTypeDesc name  [bul, num, ListOf faa] (ListOf faa)
  , fDesc      = Nothing
  , fFixity    = Prefix
  , fRules     = rBuscoFilterProteins
  }
  where
    name = "busco_filter_completeness"

rBuscoFilterProteins :: RulesFn
rBuscoFilterProteins = undefined
