mgen = load_faa "examples/sequences/Mycoplasma_genitalium_small.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
result = diamond_blastp_sensitive 1.0e-50 maga mgen
