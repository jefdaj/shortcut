query = load_faa "examples/sequences/Mycoplasma_genitalium_single.faa"
mgendb = makeblastdb_prot (load_faa "examples/sequences/Mycoplasma_genitalium_protein_refseq.faa")
magadb = makeblastdb_prot (load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa")
cyanodbs = [mgendb, magadb]
hitlists = psiblast_db_each 0.5 query cyanodbs
result = hitlists
