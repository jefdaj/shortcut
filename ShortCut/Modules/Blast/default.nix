# TODO pass proper arguments
# TODO shells for working on individual scripts (split by language?)

with import ../../../nixpkgs;

let
  myPython = pkgs.pythonPackages.python.withPackages (ps: with ps; [
    docopt
  ]);
  myR = pkgs.rWrapper.override { packages = with pkgs.rPackages; [
    dplyr
  ];};
  runDepends = [ parallel ncbi-blast myPython myR ];

in stdenv.mkDerivation {
  name = "shortcut-blast";
  src = ./.;
  inherit runDepends;
  buildInputs = [ makeWrapper ] ++ runDepends;
  builder = writeScript "builder.sh" ''
    #!/usr/bin/env bash
    source ${stdenv}/setup
    mkdir -p $out/bin
    for script in $src/*.R $src/*.py; do
      dest="$out/bin/$(basename "$script")"
      install -m755 $script $dest
      wrapProgram $dest --prefix PATH : "${pkgs.lib.makeBinPath runDepends}"
    done
  '';
}
