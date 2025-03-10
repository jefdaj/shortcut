# Both ~40% complete...
# Is that because M. genitalium is really minimal, or badly annotated?

odb9_firmicutes = busco_fetch_lineage "v2/datasets/firmicutes_odb9"
odb9_proteobacteria = busco_fetch_lineage "v2/datasets/proteobacteria_odb9"
mgen = load_faa "examples/sequences/Mycoplasma_genitalium_G37_protein_refseq.faa"
res1 = busco_proteins odb9_firmicutes mgen
res2 = busco_proteins odb9_proteobacteria mgen
result = [busco_percent_complete res1, busco_percent_complete res2]
