maga5 = load_faa "examples/sequences/Mycoplasma_genitalium_M2321_5genes.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
n = 1.0e-5
singleFwd = extract_queries (blastp n maga5 maga)
mappedFwd = extract_queries_each (blastp_each n maga5 [maga])
result = mappedFwd
singleRev = extract_queries (blastp_rev n maga maga5)
single = singleFwd | singleRev
