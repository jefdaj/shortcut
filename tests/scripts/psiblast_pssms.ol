queries = split_faa (load_faa "examples/sequences/Mycoplasma_genitalium_M2321_5genes.faa")
mgen = load_faa "examples/sequences/Mycoplasma_genitalium_protein_refseq.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
cyanodb = makeblastdb_prot_all [mgen, maga]
pssms = psiblast_train_pssms_db 1.0e-10 queries cyanodb
tablesmgen = psiblast_pssms 1.0e-10 pssms mgen
result = tablesmgen
