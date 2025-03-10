mycoplasma = load_faa_each (glob_files "examples/sequences/Mycoplasma_*_refseq.faa")
n_to_use = 4
faas_to_use = sample n_to_use mycoplasma
spres = orthofinder faas_to_use
result = length_each
  [ ortholog_in_max 0      spres faas_to_use
  , ortholog_in_max 1      spres faas_to_use
  , ortholog_in_max 2      spres faas_to_use
  , ortholog_in_max 3      spres faas_to_use
  , ortholog_in_max 4      spres faas_to_use
  , ortholog_in_max 5      spres faas_to_use
  , ortholog_in_max 10     spres faas_to_use
  , ortholog_in_max 0.1    spres faas_to_use
  , ortholog_in_max 0.2    spres faas_to_use
  , ortholog_in_max 0.3    spres faas_to_use
  , ortholog_in_max 0.4    spres faas_to_use
  , ortholog_in_max 0.5    spres faas_to_use
  , ortholog_in_max (-0.1) spres faas_to_use
  , ortholog_in_max (-1)   spres faas_to_use
  , ortholog_in_max (-10)  spres faas_to_use
  ]
