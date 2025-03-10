maga5 = load_faa "examples/sequences/Mycoplasma_genitalium_M2321_5genes.faa"
maga = makeblastdb_prot (load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa")
single = extract_queries (blastp_db 1.0e-5 maga5 maga)
mapped = extract_queries_each (blastp_db_each 1.0e-5 maga5 [maga])
result = all ([single] | mapped)
