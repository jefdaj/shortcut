maga = load_faa "examples/sequences/Mycoplasma_agalactiae_protein_refseq.faa"
mgen = load_faa "examples/sequences/Mycoplasma_genitalium_protein_refseq.faa"
mgendb = makeblastdb_prot mgen
single = extract_queries (blastp 1.0e-5 maga mgen)
mapped = extract_queries_each (blastp_each 1.0e-5 maga [mgen])
singledb = extract_queries (blastp_db 1.0e-5 maga mgendb)
mappeddb = extract_queries_each (blastp_db_each 1.0e-5
                                                maga
                                                [mgendb])
result = length_each ([single] | mapped | [singledb] | mappeddb)
