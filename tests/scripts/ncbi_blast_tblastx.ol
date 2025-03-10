genes5 = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna"
maga = gbk_to_fna "cds" (load_gbk "examples/sequences/Mycoplasma_genitalium_M2321.gbk")
hits = extract_queries (tblastx 1.0e-5 genes5 maga)
result = all (repeat hits genes5 10)
