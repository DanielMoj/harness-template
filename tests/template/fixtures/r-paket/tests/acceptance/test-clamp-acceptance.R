# Acceptance fixture for criteria K-M0-1, K-M0-2 and K-M0-3.
test_that("K-M0-1: clamp_add returns the sum below the bound", {
  expect_equal(clamp_add(1, 2), 3)
})

test_that("K-M0-2: clamp_add returns the bound above it", {
  expect_equal(clamp_add(8, 5), 10)
})

test_that("K-M0-3: the bound is configurable", {
  expect_equal(clamp_add(8, 5, upper = 20), 13)
})
