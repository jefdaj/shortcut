fnaSmall = load_fna "examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna"
faaSmall = load_faa "examples/sequences/Mycoplasma_genitalium_M2321_5genes.faa"
fnaSmallIDs = extract_ids fnaSmall
faaSmallIDs = extract_ids faaSmall
fnaSmallSeqs = extract_seqs fnaSmall fnaSmallIDs
faaSmallSeqs = extract_seqs faaSmall faaSmallIDs
fnaSmallAll = extract_ids fnaSmallSeqs
faaSmallAll = extract_ids faaSmallSeqs
fnaDiff = fnaSmallAll ~ fnaSmallIDs
faaDiff = faaSmallAll ~ faaSmallIDs
result = fnaDiff | faaDiff
