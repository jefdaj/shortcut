mgen = load_faa "examples/sequences/Mycoplasma_genitalium_small.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
mgendb = diamond_makedb mgen
result = diamond_blastp_db 1.0e-50 maga mgendb
