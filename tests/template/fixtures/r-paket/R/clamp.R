# Fixture function for the harness self-test.
clamp_add <- function(x, y, upper = 10) {
  total <- x + y
  if (total > upper) {
    return(upper)
  }
  total
}
