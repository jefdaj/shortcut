#!/usr/bin/env bash

storepaths="$(nix-build --dry-run 2>&1 | egrep '^\s*\/nix\/store')"
echo "these store paths will be attempted:\n$storepaths"

echo "building as many as possible..."
timeout 600 nix-build -j$(nproc) --quiet

echo "caching the ones that finished for next time..."
for p in $builtstorepaths; do
	[[ ! -a $p ]] && continue
	echo "caching $p"
  nix copy --to file://$HOME/nix.store $p
done
