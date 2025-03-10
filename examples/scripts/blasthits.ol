# BLAST can produce results in several formats, but OrthoLang sticks with
# tabular data (-outfmt 6) because it's compatible with many other search
# programs: PSI-BLAST, CRB-BLAST, Diamond, MMSeqs2, ... You can open the hit
# tables yourself to look at various statistics. Often you just want to get a
# list of genes matching some criteria though. Here's how you can do it inside
# OrthoLang. These examples all use BLAST, but should work the same with any
# program that produces similar hit tables.

# First you have to do a search, of course.
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
mbov = load_faa "examples/sequences/Mycoplasma_bovis_small.fa"
maga_mbov = blastp 1e-10 maga mbov

# You can make the hits more stringent afterward without re-running it
maga_mbov_stringent = filter_evalue 1e-50 maga_mbov

# The first file passed to BLAST is called the query and the second is the subject.
# You can keep only the best hit in the target file per query gene

# TODO bug running bash somewhere in here...
maga_best_mbov = best_hits maga_mbov

# You can also keep only the reciprocal best hits (those where each gene is the
# other's top hit), but you have to do the reverse search too first
# TODO move this to BlastRBH.ol
maga_mbov_rev = blastp 1e-10 mbov maga
maga_mbov_rbh = reciprocal_best maga_mbov maga_mbov_rev

# Once you're happy with the hits themselves, you can extract a list of the
# query or subject sequence IDs
maga_ids = extract_queries maga_mbov_rbh
mbov_ids = extract_targets maga_mbov_rbh

# See the Sets, Plots, and Scores modules for ways to compare the lists.
# TODO add direct homolog pairs extraction (in a separate module?)

# Finally, if you just want a rough idea how many hits you got for each method,
# length and length_each are helpful
result = length_each [maga_ids, extract_queries maga_best_mbov]
