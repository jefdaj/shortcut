small = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_single.fna"
large = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna"
fwds = extract_queries (blastn 1.0e-5 small large)
srevs = extract_queries (blastn_rev 1.0e-5 large small)
mrevs = any (extract_queries_each (blastn_rev_each 1.0e-5
                                                   large
                                                   [small]))
result = some [fwds, srevs, mrevs]
