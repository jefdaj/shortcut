query = load_faa "examples/sequences/Mycoplasma_genitalium_single.faa"
mgen = load_faa "examples/sequences/Mycoplasma_genitalium_protein_refseq.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
cyanodb = makeblastdb_prot_all [mgen, maga]
pssm = psiblast_train_db 1.0e-10 query cyanodb
single = psiblast_pssm_db 1.0e-10 pssm cyanodb
result = single
