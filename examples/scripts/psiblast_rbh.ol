g1 = load_faa "examples/sequences/PCC_6803_genes.faa"
g2 = concat_faa [gbk_to_faa "cds" (load_gbk "examples/sequences/PCC_7942_chr.gbk"),
                 gbk_to_faa "cds" (load_gbk "examples/sequences/PCC_7942_pANL.gbk")]

# to speed up the example, we only train 10 random pssms out of 3000+
g1_10_genes = sample 10 (split_faa g1)
pssms = psiblast_train_pssms 1e-10 g1_10_genes g2
result = pssms

# TODO finish this
