# this one is different because it doesn't include a title. TODO should it?

l1 = range_integers 1 10
l2 = range_integers 3 15
l3 = range_integers 3 20
l4 = range_integers 15 50
l5 = range_integers 0 10
l6 = range_integers 0 100

d_one   = venndiagram [l1]
d_two   = venndiagram [l1, l2]
d_three = venndiagram [l1, l2, l3]
d_four  = venndiagram [l1, l2, l3, l4]
d_five  = venndiagram [l1, l2, l3, l4, l5]
d_six   = venndiagram [l1, l2, l3, l4, l5, l6] # this should switch to UpSetR

# this caught a bug in the label ordering once
d_five_unordered = venndiagram [l2,l5,l1,l3,l4]

result = [d_one, d_two, d_three, d_four, d_five, d_five_unordered, d_six]
