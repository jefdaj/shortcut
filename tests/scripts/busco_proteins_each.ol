odb9_firmicutes = busco_fetch_lineage "v2/datasets/firmicutes_odb9"
mgen = load_faa "examples/sequences/Mycoplasma_genitalium_G37_protein_refseq.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_PG2_protein_refseq.faa"
result = busco_proteins_each odb9_firmicutes [maga, mgen]
