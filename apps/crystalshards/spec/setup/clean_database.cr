Spec.before_each do
  AppDatabase.truncate

  # The second connection is cleaned on the same schedule as the first. Its
  # rows are planted by hand rather than by a factory, so a row left behind by
  # one example is a row the next example's UPDATE silently matches.
  DocsTestDatabase.truncate
end
