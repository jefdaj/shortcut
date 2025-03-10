# Repeating 3 times eliminated a few inconsistent hits, so should we repeat a
# bunch more to eliminate more? Maybe, but at some point there will be
# diminishing returns. For demonstration purposes we'll try it up to 100 times
# and graph progress...

# TODO show the new "repeat until convergence" function here

include "maga-vs-mgen-blastp-rbh-3x.ol"

n_hits_by_n_repeats = score_repeats
                        (length solidHitIDs)
                        n_repeats
                        [1,2,3,4,5,6,7,8,9,10,15,20,30,50,75,100]

result = linegraph
           "After X repeats, how many genes have been found every time?"
           n_hits_by_n_repeats
