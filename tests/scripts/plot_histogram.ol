xvar = 1
yvar = 1200 * xvar
scores = score_repeats yvar
                       xvar
                       [1, 2, 3, 4, 5, 2, 2, 4, 1, 3, 1, 1, 1, 1]
xvars = extract_scored scores
yvars = extract_scores scores
plots = [histogram "histogram of xvar inputs" xvars,
         histogram "histogram of yvar scores" yvars,
         histogram "histogram of unnamed (inline) nums"
                   [1, 2, 3, 4, 5, 2, 2, 4, 1, 3, 1, 1, 1, 1]]
result = plots
