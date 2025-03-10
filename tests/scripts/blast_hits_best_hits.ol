mgen = load_faa "examples/sequences/Mycoplasma_genitalium_small.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
hits = blastp 1.0e-5 mgen maga
hits3 = repeat hits mgen 3
best3 = best_hits_each hits3
result = length (all (extract_targets_each best3))
