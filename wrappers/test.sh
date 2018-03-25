#!/bin/bash

mkdir -p $(pwd) # wtf why is this needed
sleep 1

# print a message if log level is set (from within ShortCut or by the user)
# TODO send this to a file rather than stdout?
# log() { [[ -z $SHORTCUT_LOGLEVEL ]] || echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@"; }

# Common options for all srun commands
SRUN="srun --account=co_rosalind --partition=savio2_htc --qos=rosalind_htc2_normal"
SRUN="$SRUN --chdir $(pwd) --quiet"
# TODO --exclusive -N1 -n1?

srun_single() {
  # This is mostly for crb-blast so far
  cmd="$@"
  srun="$SRUN --cpus-per-task=4 --nodes=1-1 --ntasks=1 --time=99:00:00"
  cmd="$srun $cmd"
  echo "$cmd"
}

srun_parallel() {
  # monkey-patches a parallel call to run its individual commands via slurm
  # note that it's brittle and only works on shortcut-generated blast commands
  cmd="$@"
  before="$(echo "$cmd" | cut -d' ' -f-10)" # ... --pipe
  after="$(echo "$cmd" | cut -d' ' -f11-)"  # '*blast* ...
  srun="$SRUN --cpus-per-task=1 --nodes=1-1 --ntasks=1 --time=99:00:00"
  cmd="${before} $srun ${after}"
  echo "$cmd"
}

# If none of the special cases below match, this will run as-is.
CMD="$@"

if [[ $CMD =~ "--recstart" ]]; then
  # Make parallel blast run individual commands via srun
  CMD="$(srun_parallel "$CMD")"
elif [[ $CMD == "crb-blast"* ]]; then
  # crb-blast spawns parallel jobs itself, so run in a single srun
  CMD="$(srun_single "$CMD")"
fi

# Run the finished command
# TODO incorporate a proper logfile
echo "$CMD"  >> /tmp/test.log
eval "$CMD" 2>> /tmp/test.log
