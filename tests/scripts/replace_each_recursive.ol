ind = 547
ind2 = 557
ind3 = 563
dep = 569 * ind * ind2 * ind3
rep1 = replace_each dep ind [571, 577]
rep2 = replace_each rep1 ind2 [587, 701, 709, 719, 727, 733]
rep3 = replace_each rep2 ind3 [739, 743, 877]
result = rep3
