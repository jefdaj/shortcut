# TODO could everything in here go in a separate haskell-package.nix or similar?

# to work on a specific module, substitute it here and enter nix-shell
# TODO make an example .nix file for that

with import ./nixpkgs;
let
  sources = import ./nix/sources.nix {};

  # Things needed at runtime. Modules are only the scripts called by ortholang,
  # not their indirect (propagated) dependencies since those may conflict.
  # TODO add the ones that don't conflict for easier development?
  inherit (import ./dependencies.nix) runDepends;

  # Haskell stuff! It starts with the upstream haskellPackages set for the
  # chosen compiler, then we override a few dependencies, and finally we define
  # the ortholang package.
  inherit (pkgs.haskell.lib) overrideCabal;
  myGHC = "ghc884";
  myHs = pkgs.haskell.packages.${myGHC}.override {
    overrides = hpNew: hpOld: {

      # Packages that can be fixed with simple overrides
      progress-meter = overrideCabal hpOld.progress-meter (_: {
        broken = false;
        jailbreak = true;
      });

      # Packages that had to be forked
      logging = hpOld.callPackage sources.logging {};
      docopt  = hpOld.callPackage sources.docopt {};

      # The ortholang package, which includes the main binary
      # TODO final wrapper with +RTS -N -RTS?
      # TODO get back the enable{Library,Executable}Profiling options?
      ortholang = overrideCabal (hpOld.callCabal2nix "OrthoLang" ./. {}) (drv: {

        # surprisingly, this works as a drop-in replacement for filterSource
        # except with better filtering out of non-source files
        # based on https://github.com/NixOS/nix/issues/885#issuecomment-381904833
        src = builtins.fetchGit { url = ./.; };

        # TODO remove these? are they still needed?
        buildDepends = (drv.buildDepends or [])  ++ runDepends ++ [
          makeWrapper zlib.dev zlib.out pkgconfig
        ];

        # TODO PYTHONPATH?
        postInstall = ''
          ${drv.postInstall or ""}
          wrapProgram "$out/bin/ortholang" \
            --set LANG en_US.UTF-8 \
            --set LANGUAGE en_US.UTF-8 \
            --prefix PATH : "${pkgs.lib.makeBinPath runDepends}"'' +
        (if stdenv.hostPlatform.system == "x86_64-darwin" then "" else '' \
          --set LOCALE_ARCHIVE "${glibcLocales}/lib/locale/locale-archive"
        '');

        shellHook = ''
          ${drv.shellHook or ""}
          export LANG=en_US.UTF-8
          export LANGUAGE=en_US.UTF-8
          # export TASTY_HIDE_SUCCESSES=True
        '' ++
        (if stdenv.hostPlatform.system == "x86_64-darwin" then "" else ''
          export LOCALE_ARCHIVE="${glibcLocales}/lib/locale/locale-archive"
        '');

      });

    };
  };

in {

  # This is the main build target for default.nix
  project = myHs.ortholang;

  # And this is the development environment for shell.nix
  # Most of the shell stuff is here, but shellHook above is also important
  shell = myHs.shellFor {

    # TODO would there be any reason to add other packages here?
    packages = p: with p; [ myHs.ortholang ];

    # Put any packages you want during development here.
    # You can optionally go "full reproducible" by adding your text editor
    # and using `nix-shell --pure`, but you'll also have to add some common
    # unix tools as you go.
    buildInputs = with myHs; [
      ghcid
      hlint
      stack
    ];

    # Run a local Hoogle instance like this:
    # nix-shell --run hoogle server --port=8080 --local --haskell
    withHoogle = true;
  };
}
