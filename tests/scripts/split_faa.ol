faas1 = split_faa (load_faa "examples/sequences/Mycoplasma_genitalium_M2321_5genes.faa")
faas2 = split_faa (gbk_to_faa "cds" (load_gbk "examples/sequences/Mycoplasma_agalactiae_PG2.gbk"))
lengths = length_each [faas1, faas2]
result = lengths
