mgen = load_faa "examples/sequences/Mycoplasma_genitalium_protein_refseq.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
query = load_faa "examples/sequences/Mycoplasma_genitalium_single.faa"
pssms = psiblast_train_each 0.1 query [mgen, maga]
result = length pssms
