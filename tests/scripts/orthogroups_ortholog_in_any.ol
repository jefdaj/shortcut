mycoplasma = load_faa_each (glob_files "examples/sequences/Mycoplasma_*_refseq.faa")
ofres = orthofinder (sample 3 mycoplasma)
shared = ortholog_in_any ofres mycoplasma
result = shared
