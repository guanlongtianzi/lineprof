% Generated by roxygen2 (4.1.0): do not edit by hand
% Please edit documentation in R/RcppExports.R
\name{pause}
\alias{pause}
\title{Pause execution}
\usage{
pause(sec)
}
\arguments{
\item{sec}{Number of seconds to pause (millsecond resolution).}
}
\description{
This is similar to \code{\link{Sys.sleep}} but is captured during
profiling, making it useful when generating simple examples.
}

