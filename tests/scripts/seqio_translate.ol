single = translate (load_fna "examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna")
mapped = translate_each (load_fna_each ["examples/sequences/Mycoplasma_genitalium_M2321_5genes.fna"])
result = [single] | mapped
