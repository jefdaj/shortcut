single = load_faa "examples/sequences/Mycoplasma_genitalium_single.faa"
genes5 = load_faa "examples/sequences/Mycoplasma_genitalium_M2321_5genes.faa"
singles = [makeblastdb_prot single, makeblastdb_prot genes5]
each = makeblastdb_prot_each [single, genes5]
both = makeblastdb_prot_all [single, genes5]
result = length_each [singles, each, singles | each, [both]]
