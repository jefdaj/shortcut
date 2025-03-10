query = load_faa "examples/sequences/Mycoplasma_genitalium_single.faa"
mgen = makeblastdb_prot (load_faa "examples/sequences/Mycoplasma_genitalium_protein_refseq.faa")
maga = makeblastdb_prot (load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa")
pssm = psiblast_train_db 1.0e-2 query mgen
hitlists = psiblast_pssm_db_each 1.0e-2 pssm [mgen, maga]
result = hitlists
