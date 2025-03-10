mgen = load_faa "examples/sequences/Mycoplasma_genitalium_small.faa"
maga = gbk_to_fna "cds" (load_gbk "examples/sequences/Mycoplasma_agalactiae_PG2.gbk")
db = diamond_makedb mgen
result = diamond_blastx_db 1.0e-45 maga db
