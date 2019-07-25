module ShortCut.Modules.OrthoFinder
  where

-- TODO write a function to extract_seqs from multiple fastas at once, useful here + elsewhere?
-- TODO can all "extract" functions be renamed with "list"?
-- TODO try DIAMOND, MMseqs2

import Development.Shake
import ShortCut.Core.Types

import Data.List                   (isPrefixOf)
import ShortCut.Core.Actions       (debugA, debugNeed, readPaths, symlink, runCmd, CmdDesc(..))
import ShortCut.Core.Compile.Basic (defaultTypeCheck, rSimple)
import ShortCut.Core.Locks         (withWriteLock')
import ShortCut.Core.Paths         (CutPath, toCutPath, fromCutPath)
import ShortCut.Core.Util          (digest, readFileStrict, unlessExists)
import ShortCut.Modules.SeqIO      (faa)
import System.Directory            (createDirectoryIfMissing, renameDirectory)
import System.FilePath             ((</>), (<.>), takeFileName)
import System.Exit                 (ExitCode(..))

cutModule :: CutModule
cutModule = CutModule
  { mName = "OrthoFinder"
  , mDesc = "Inference of orthologs, orthogroups, the rooted species, gene trees and gene duplcation events tree"
  , mTypes = [faa, ofr]
  , mFunctions =
      [ orthofinder
      ]
  }

ofr :: CutType
ofr = CutType
  { tExt  = "ofr"
  , tDesc = "OrthoFinder results"
  , tShow = \_ ref path -> do
      txt <- readFileStrict ref path
      return $ unlines $ take 17 $ lines txt
  }

-----------------
-- orthofinder --
-----------------

orthofinder :: CutFunction
orthofinder = let name = "orthofinder" in CutFunction
  { fName      = name
  , fTypeDesc  = mkTypeDesc  name [ListOf faa] ofr
  , fTypeCheck = defaultTypeCheck [ListOf faa] ofr
  , fFixity    = Prefix
  , fRules     = rSimple aOrthofinder
  }

-- TODO do blast separately and link to outputs from the WorkingDirectory dir, and check if same results
-- TODO what's diamond blast? do i need to add it?
aOrthofinder :: CutConfig -> Locks -> HashedIDsRef -> [CutPath] -> Action ()
aOrthofinder cfg ref _ [out, faListPath] = do

  let tmpDir = cfgTmpDir cfg </> "cache" </> "orthofinder" </> digest faListPath
      resDir = tmpDir </> "result"
      statsPath = toCutPath cfg $ resDir </> "Comparative_Genomics_Statistics" </> "Statistics_Overall.tsv"

  -- unlessExists resDir $ do
  liftIO $ createDirectoryIfMissing True $ tmpDir </> "OrthoFinder"
  withWriteLock' ref (tmpDir </> "lock") $ do

    faPaths <- readPaths cfg ref faListPath'
    let faPaths' = map (fromCutPath cfg) faPaths
    debugNeed cfg "aOrthofinder" faPaths'
    let faLinks = map (\p -> toCutPath cfg $ tmpDir </> (takeFileName $ fromCutPath cfg p)) faPaths
    mapM_ (\(p, l) -> symlink cfg ref l p) $ zip faPaths faLinks

    runCmd cfg ref $ CmdDesc
      { cmdBinary = "orthofinder.sh"
      , cmdArguments = [out'' <.> "out", tmpDir, "diamond"]
      , cmdFixEmpties = False
      , cmdParallel = False -- TODO fix this? it fails because of withResource somehow
      , cmdOptions = []
      , cmdInPatterns = faPaths'
      , cmdOutPath = out'' <.> "out"
      , cmdExtraOutPaths = [out'' <.> "err", tmpDir]
      , cmdSanitizePaths = [] -- TODO use this?
      , cmdExitCode = ExitSuccess
      , cmdRmPatterns = [out'', tmpDir]
      }
 
    -- TODO AHA! probably have to tell shake how to track these. split into the main action and another linking one
    -- TODO or just patch orthofinder not to do the date thing

    -- find the results dir and link it to a name that doesn't include today's date
    resName <- fmap last $ fmap (filter $ \p -> "Results_" `isPrefixOf` p) $ getDirectoryContents $ tmpDir </> "OrthoFinder"
    -- liftIO $ renameDirectory (tmpDir </> "OrthoFinder" </> resName) resDir
    symlink cfg ref (toCutPath cfg resDir) (toCutPath cfg $ tmpDir </> "OrthoFinder" </> resName)

    -- let resPath = tmpDir </> "Orthofinder" </> resName
    symlink cfg ref out statsPath
    -- liftIO $ putStrLn $ "resName: " ++ show resName
    -- liftIO $ putStrLn $ "resPath: " ++ show resPath
    -- liftIO $ putStrLn $ "resDir: " ++ show resDir
    -- liftIO $ putStrLn $ "resPath: " ++ show resPath
    -- liftIO $ putStrLn $ "srcPath: " ++ show srcPath
    -- TODO ok to have inside unlessExists?
    -- return ()
  where
    out'        = fromCutPath cfg out
    faListPath' = fromCutPath cfg faListPath
    out''       = debugA cfg "aOrthofinder" out' [out', faListPath']

aOrthofinder _ _ _ args = error $ "bad argument to aOrthofinder: " ++ show args
