#!/bin/bash

# Wrapper for the Berkeley Computational Genomics Resource Laboratory (CGRL).
# It should work with minor changes on any system that uses the SLURM scheduler
# though if you adjust the SRUN command to match your system requirements.

# Note that you also need to set TMPDIR to something shared across machines
# before invoking shortcut. For example I use:
# export TMPDIR=/global/scratch/jefdaj/shortcut-test
# Otherwise you'll get lots of srun errors "cannot chdir to /tmp/whatever..."

# TODO set logfile from shortcut config

# Common options for all srun commands
SRUN="srun --account=co_rosalind --partition=savio2_htc --qos=rosalind_htc2_normal"
SRUN="$SRUN --chdir $(pwd) --quiet"

limit_total_jobs() {
  # Beyond 100-200 jobs at once, random SLURM bugs seem to surface which is a
  # bad time for everyone involved! This helps prevent that.
  #
  # Note that srun_parallel launches jobs in batches, so you might get as many
  # as maxjobs + -jwhatever. But if you set -j too low and run one big BLAST
  # operation, you'll only get -j jobs at once. This script is set to spawn up
  # to 80 jobs per parallel operation and never more than 180 total.

  maxjobs=50
  while [[ "$(squeue -u $(whoami) | wc -l)" -gt $maxjobs ]]; do
    sleep 5
  done
}

srun_crb() {
  limit_total_jobs
  srun="$SRUN --cpus-per-task=7 --nodes=1-1 --ntasks=1 --mem=50G --time=99:00:00"
  echo "$srun $@"
}

srun_quick() {
  limit_total_jobs
  echo "$SRUN --cpus-per-task=1 --nodes=1-1 --ntasks=1 --time=00:10:00 $@"
}

srun_parallel() {
  # monkey-patches a parallel call to run its individual commands via slurm
  # note that it's brittle and only works on shortcut-generated blast commands
  sleep $(shuf -i 0-300 -n1) # prevent all trying to limit_total_jobs at once
  limit_total_jobs
  cmd="$@"
  before="$(echo "$cmd" | cut -d' ' -f-12)" # ... --pipe
  after="$(echo "$cmd" | cut -d' ' -f13-)"  # '*blast* ...

  # Using -N1 here says to run each record (sequence) separately. That slows it
  # down significantly, but on the rare occasion a sequence has an error like
  # an invalid amino acid, only that one will be exluded from the hits.
  # Instead, you might want to watch the output for errors, then fix them and
  # re-run any affected genomes.
  # TODO can/should I make it fail if one task fails?
  #      (possibly fixed in newer blast+ than 2.2.29?)
  pargs="-j10 -N1 --delay 0.5" # additional parallel args

  # TODO --exclusive?
  # TODO any chance one will take more than 10 min?
  srun="$SRUN --cpus-per-task=1 --nodes=1-1 --ntasks=1 --time=00:10:00"
  cmd="${before} ${pargs} ${srun} ${after}"
  echo "$cmd"
}

# If none of the special cases below match, this will run as-is.
CMD="$@"

# Make parallel blast run individual commands via srun.
# This one is tricky and may run better with adjustments to the -j parameter.
if [[ $CMD =~ "--recstart" ]]; then
  CMD="$(srun_parallel "$CMD")"

# crb-blast spawns parallel jobs itself, so run in a single srun.
# TODO would this run faster on savio than savio2_htc with more cores?
elif [[ $CMD == "crb-blast"* ]]; then
  CMD="$(srun_crb "$CMD")"

# These are quick commands that may be better to run locally depending on the
# queue. Check `squeue` and remove any that are piling up. Some that seem
# trivial like `cat` and `cut` can be IO-bound when many run at once on the
# same machine.
elif [[ $CMD == md5sum*      ||
        $CMD == makeblastdb* ||
        $CMD == blastdbget*  ||
        $CMD == cut*         ||
        $CMD == cat*         ||
        $CMD =~ ".py"        ||
        $CMD =~ ".R"         ]]; then
  CMD="$(srun_quick "$CMD")"

fi

run() {
 echo "$@"  >> /tmp/wrapper.log
 eval "$@" 2>> /tmp/wrapper.log
}

# Run the finished command
run "$CMD"
