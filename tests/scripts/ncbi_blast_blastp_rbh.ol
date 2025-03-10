mgen = load_faa "examples/sequences/Mycoplasma_genitalium_protein_refseq.faa"
maga = load_faa "examples/sequences/Mycoplasma_agalactiae_small.faa"
n = 1.0e-5
fwd = blastp n mgen maga
rev1 = blastp n maga mgen
rev2 = blastp_rev n mgen maga
rbh1 = reciprocal_best fwd rev1
rbh2 = reciprocal_best fwd rev2
rbh3 = blastp_rbh n mgen maga
rbh4 = blastp_rbh n maga mgen
lists = extract_queries_each [rbh1, rbh2, rbh3] |
        extract_targets_each [rbh4]
result = any lists ~ all lists
