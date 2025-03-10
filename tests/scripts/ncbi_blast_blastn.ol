mgen = gbk_to_fna "cds" (load_gbk "examples/sequences/Mycoplasma_genitalium_M2321.gbk")
mbov = gbk_to_fna "cds" (load_gbk "examples/sequences/Mycoplasma_bovis_HB0801-P115.gbk")
single = extract_queries (blastn 1.0e-5 mbov mgen)
mapped = extract_queries_each (blastn_each 1.0e-5 mbov [mgen])
result = [single] | mapped
