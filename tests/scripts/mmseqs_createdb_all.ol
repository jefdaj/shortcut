maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
maga_db = mmseqs_createdb_all [maga]
result = maga_db
