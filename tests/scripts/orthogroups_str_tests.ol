# These functions aren't meant to be user-facing,
# but help check that their non-str equivalents will work properly.

# kind of like orthogroups
g1 = ["1", "2", "3"]
g2 = ["2", "3", "4"]
g3 = ["4", "5"]
g4 = ["6"]
groups = [g1, g2, g3, g4]

# kind of like fasta seqids
f1 = ["1", "2", "3"]
f2 = ["4", "5", "6"]
f3 = ["one", "two", "three"]
fastas = [f1, f2, f3]

result =
  [ ortholog_in_any_str groups fastas
  , ortholog_in_all_str groups fastas

  , ortholog_in_min_str 0 groups fastas
  , ortholog_in_min_str 1 groups fastas
  , ortholog_in_min_str 2 groups fastas
  , ortholog_in_min_str 3 groups fastas

  , ortholog_in_max_str 0 groups fastas
  , ortholog_in_max_str 1 groups fastas
  , ortholog_in_max_str 2 groups fastas
  , ortholog_in_max_str 3 groups fastas

  , ortholog_in_min_str (-1) groups fastas
  , ortholog_in_min_str (-2) groups fastas
  , ortholog_in_min_str (-3) groups fastas

  , ortholog_in_min_str 0.1 groups fastas
  , ortholog_in_min_str 0.2 groups fastas
  , ortholog_in_min_str 0.3 groups fastas
  , ortholog_in_min_str 0.4 groups fastas
  , ortholog_in_min_str 0.5 groups fastas
  , ortholog_in_min_str 0.6 groups fastas
  , ortholog_in_min_str 0.7 groups fastas
  , ortholog_in_min_str 0.8 groups fastas
  , ortholog_in_min_str 0.9 groups fastas

  , ortholog_in_max_str 0.1 groups fastas
  , ortholog_in_max_str 0.2 groups fastas
  , ortholog_in_max_str 0.3 groups fastas
  , ortholog_in_max_str 0.4 groups fastas
  , ortholog_in_max_str 0.5 groups fastas
  , ortholog_in_max_str 0.6 groups fastas
  , ortholog_in_max_str 0.7 groups fastas
  , ortholog_in_max_str 0.8 groups fastas
  , ortholog_in_max_str 0.9 groups fastas
  ]
