maga5 = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna"
maga = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna"
single = extract_queries (megablast 1.0e-5 maga5 maga)
mapped = extract_queries_each (megablast_each 1.0e-5 maga5 [maga])
result = [single] | mapped
