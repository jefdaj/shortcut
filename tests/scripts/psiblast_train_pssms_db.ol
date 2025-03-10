mgen = load_faa "examples/sequences/Mycoplasma_genitalium_protein_refseq.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
cyanodb = makeblastdb_prot_all [mgen, maga]
queries = split_faa (load_faa "examples/sequences/Mycoplasma_genitalium_M2321_5genes.faa")
pssms = psiblast_train_pssms_db 1.0e-10 queries cyanodb
result = pssms
