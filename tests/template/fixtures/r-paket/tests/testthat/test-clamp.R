test_that("clamp_add adds below the bound", {
  expect_equal(clamp_add(2, 3), 5)
})
