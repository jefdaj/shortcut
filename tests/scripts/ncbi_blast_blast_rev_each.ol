small = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_single.fna"
large = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna"
srevs = extract_queries (blastn_rev 1.0e-10 large small)
mrevs = extract_queries_each (blastn_rev_each 1.0e-10 large [small])
result = mrevs ~ [srevs]
