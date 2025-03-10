mgen = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna"
maga = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna"
n = 1.0e-5
fwd = blastn n mgen maga
rev1 = blastn n maga mgen
rev2 = blastn_rev n mgen maga
rbh1 = reciprocal_best fwd rev1
rbh2 = reciprocal_best fwd rev2
rbh3 = blastn_rbh n mgen maga
rbh4 = blastn_rbh n maga mgen
lists = extract_queries_each [rbh1, rbh2, rbh3] |
        extract_targets_each [rbh4]
result = any lists ~ all lists
