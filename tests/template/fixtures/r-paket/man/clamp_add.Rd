\name{clamp_add}
\alias{clamp_add}
\title{Add Two Numbers With an Upper Bound}
\usage{
clamp_add(x, y, upper = 10)
}
\arguments{
\item{x, y}{Numbers to add.}

\item{upper}{Upper bound of the result.}
}
\value{
The sum of \code{x} and \code{y}, but at most \code{upper}.
}
\description{
Fixture function of the harness self-test.
}
\examples{
clamp_add(2, 3)
}
