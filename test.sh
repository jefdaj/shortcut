#!/usr/bin/env bash

# remember to export TMPDIR=<some shared location> before testing on HPC clusters!
# script arguments will be passed to ortholang --test
# other possible tasty settings: https://hackage.haskell.org/package/tasty

test_filter='version'

set -e
set -o pipefail

export TASTY_QUICKCHECK_TESTS=100
export TASTY_COLOR="always"
export TASTY_QUICKCHECK_SHOW_REPLAY=True
# export TASTY_HIDE_SUCCESSES=True
# [[ -z "$TMPDIR" ]] && export TMPDIR=/tmp

timestamp=$(date '+%Y-%m-%d_%H:%M')

nix_args="--pure -j2"
# stack_cmd="stack build && stack exec ortholang -- --test $test_filter"

log="ortholang-${test_filter}-${timestamp}.log"

set -x
# nix-shell shell.nix $nix_args --command "$stack_cmd; exit" 2>&1 | tee -a $log
nix-build $nix_args 2>&1 | tee -a $log
./result/bin/ortholang \
				--test "$test_filter" \
				2>&1 | tee -a $log

# test with the demo server cache too
# (just blastp functions for now to keep from getting too big)
# stack_cmd_2="stack exec shortcut -- --shared http://shortcut.pmb.berkeley.edu/shared --test $test_filter"
# nix-shell shell.nix $nix_args --command "$stack_cmd_2; exit" 2>&1 | tee -a $log
./result/bin/ortholang \
				--shared http://shortcut.pmb.berkeley.edu/shared \
				--test "$test_filter" \
				2>&1 | tee -a $log

# log="ortholang-test_${timestamp}.log"
# test_args="+RTS -IO -N -RTS --test biomartr"
# cmd="./result/bin/ortholang $test_args"
# echo "$cmd" | tee $log
# $cmd 2>&1 | tee -a $log
