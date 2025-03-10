# TODO why is this this only one with issues loading?
# these cause the error: best5fwd, best5rec
# these don't: bestFwd, bestRec

maga = load_faa "examples/sequences/Mycoplasma_agalactiae_PG2_protein_refseq.faa"
mgen = load_faa "examples/sequences/Mycoplasma_genitalium_protein_refseq.faa"
fwdHits = blastp 1.0e-5 maga mgen
revHits = blastp 1.0e-5 mgen maga
bestFwd = best_hits fwdHits
bestRec = reciprocal_best fwdHits revHits
best5fwd = repeat bestFwd maga 5
best5rec = repeat bestRec maga 5
solidFwd = all (extract_queries_each best5fwd)
solidRec = all (extract_queries_each best5rec)
result = length solidRec
