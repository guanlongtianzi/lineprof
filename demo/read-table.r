read.table2 <-
  function(file, header = FALSE, sep = "", quote = "\"'", dec = ".",
    row.names, col.names, as.is = !stringsAsFactors,
    na.strings = "NA", colClasses = NA,
    nrows = -1, skip = 0,
    check.names = TRUE, fill = !blank.lines.skip,
    strip.white = FALSE, blank.lines.skip = TRUE,
    comment.char = "#", allowEscapes = FALSE, flush = FALSE,
    stringsAsFactors = default.stringsAsFactors(),
    fileEncoding = "", encoding = "unknown", text)
  {
    if (missing(file) && !missing(text)) {
      file <- textConnection(text)
      on.exit(close(file))
    }
    if(is.character(file)) {
      file <- if(nzchar(fileEncoding))
        file(file, "rt", encoding = fileEncoding) else file(file, "rt")
      on.exit(close(file))
    }
    if(!inherits(file, "connection"))
      stop("'file' must be a character string or connection")
    if(!isOpen(file, "rt")) {
      open(file, "rt")
      on.exit(close(file))
    }
    
    if(skip > 0L) readLines(file, skip)
    ## read a few lines to determine header, no of cols.
    nlines <- n0lines <- if (nrows < 0L) 5 else min(5L, (header + nrows))
    
    lines <- .External(C_readtablehead, file, nlines, comment.char,
      blank.lines.skip, quote, sep)
    nlines <- length(lines)
    if(!nlines) {
      if(missing(col.names)) stop("no lines available in input")
      rlabp <- FALSE
      cols <- length(col.names)
    } else {
      if(all(!nzchar(lines))) stop("empty beginning of file")
      if(nlines < n0lines && file == 0L)  { # stdin() has reached EOF
        pushBack(c(lines, lines, ""), file)
        on.exit((clearPushBack(stdin())))
      } else pushBack(c(lines, lines), file)
      first <- scan(file, what = "", sep = sep, quote = quote,
        nlines = 1, quiet = TRUE, skip = 0,
        strip.white = TRUE,
        blank.lines.skip = blank.lines.skip,
        comment.char = comment.char, allowEscapes = allowEscapes,
        encoding = encoding)
      col1 <- if(missing(col.names)) length(first) else length(col.names)
      col <- numeric(nlines - 1L)
      if (nlines > 1L)
        for (i in seq_along(col))
          col[i] <- length(scan(file, what = "", sep = sep,
            quote = quote,
            nlines = 1, quiet = TRUE, skip = 0,
            strip.white = strip.white,
            blank.lines.skip = blank.lines.skip,
            comment.char = comment.char,
            allowEscapes = allowEscapes))
      cols <- max(col1, col)
      
      ##	basic column counting and header determination;
      ##	rlabp (logical) := it looks like we have column names
      
      rlabp <- (cols - col1) == 1L
      if(rlabp && missing(header))
        header <- TRUE
      if(!header) rlabp <- FALSE
      
      if (header) {
        ## skip over header
        .External(C_readtablehead, file, 1L, comment.char,
          blank.lines.skip, quote, sep)
        if(missing(col.names)) col.names <- first
        else if(length(first) != length(col.names))
          warning("header and 'col.names' are of different lengths")
        
      } else if (missing(col.names))
        col.names <- paste0("V", 1L:cols)
      if(length(col.names) + rlabp < cols)
        stop("more columns than column names")
      if(fill && length(col.names) > cols)
        cols <- length(col.names)
      if(!fill && cols > 0L && length(col.names) > cols)
        stop("more column names than columns")
      if(cols == 0L) stop("first five rows are empty: giving up")
    }
    
    if(check.names) col.names <- make.names(col.names, unique = TRUE)
    if (rlabp) col.names <- c("row.names", col.names)
    
    nmColClasses <- names(colClasses)
    if(length(colClasses) < cols)
      if(is.null(nmColClasses)) {
        colClasses <- rep_len(colClasses, cols)
      } else {
        tmp <- rep_len(NA_character_, cols)
        names(tmp) <- col.names
        i <- match(nmColClasses, col.names, 0L)
        if(any(i <= 0L))
          warning("not all columns named in 'colClasses' exist")
        tmp[ i[i > 0L] ] <- colClasses
        colClasses <- tmp
      }
    
    
    ##	set up for the scan of the file.
    ##	we read unknown values as character strings and convert later.
    
    what <- rep.int(list(""), cols)
    names(what) <- col.names
    
    colClasses[colClasses %in% c("real", "double")] <- "numeric"
    known <- colClasses %in% c("logical", "integer", "numeric", "complex",
      "character", "raw")
    what[known] <- sapply(colClasses[known], do.call, list(0))
    what[colClasses %in% "NULL"] <- list(NULL)
    keep <- !sapply(what, is.null)
    
    data <- scan(file = file, what = what, sep = sep, quote = quote,
      dec = dec, nmax = nrows, skip = 0,
      na.strings = na.strings, quiet = TRUE, fill = fill,
      strip.white = strip.white,
      blank.lines.skip = blank.lines.skip, multi.line = FALSE,
      comment.char = comment.char, allowEscapes = allowEscapes,
      flush = flush, encoding = encoding)
    
    nlines <- length(data[[ which.max(keep) ]])
    
    ##	now we have the data;
    ##	convert to numeric or factor variables
    ##	(depending on the specified value of "as.is").
    ##	we do this here so that columns match up
    
    if(cols != length(data)) { # this should never happen
      warning("cols = ", cols, " != length(data) = ", length(data),
        domain = NA)
      cols <- length(data)
    }
    
    if(is.logical(as.is)) {
      as.is <- rep_len(as.is, cols)
    } else if(is.numeric(as.is)) {
      if(any(as.is < 1 | as.is > cols))
        stop("invalid numeric 'as.is' expression")
      i <- rep.int(FALSE, cols)
      i[as.is] <- TRUE
      as.is <- i
    } else if(is.character(as.is)) {
      i <- match(as.is, col.names, 0L)
      if(any(i <= 0L))
        warning("not all columns named in 'as.is' exist")
      i <- i[i > 0L]
      as.is <- rep.int(FALSE, cols)
      as.is[i] <- TRUE
    } else if (length(as.is) != cols)
      stop(gettextf("'as.is' has the wrong length %d  != cols = %d",
        length(as.is), cols), domain = NA)
    
    do <- keep & !known # & !as.is
    if(rlabp) do[1L] <- FALSE # don't convert "row.names"
    for (i in (1L:cols)[do]) {
      data[[i]] <-
        if (is.na(colClasses[i]))
          type.convert(data[[i]], as.is = as.is[i], dec = dec,
            na.strings = character(0L))
      ## as na.strings have already been converted to <NA>
      else if (colClasses[i] == "factor") as.factor(data[[i]])
      else if (colClasses[i] == "Date") as.Date(data[[i]])
      else if (colClasses[i] == "POSIXct") as.POSIXct(data[[i]])
      else methods::as(data[[i]], colClasses[i])
    }
    
    ##	now determine row names
    compactRN <- TRUE
    if (missing(row.names)) {
      if (rlabp) {
        row.names <- data[[1L]]
        data <- data[-1L]
        keep <- keep[-1L]
        compactRN <- FALSE
      }
      else row.names <- .set_row_names(as.integer(nlines))
    } else if (is.null(row.names)) {
      row.names <- .set_row_names(as.integer(nlines))
    } else if (is.character(row.names)) {
      compactRN <- FALSE
      if (length(row.names) == 1L) {
        rowvar <- (1L:cols)[match(col.names, row.names, 0L) == 1L]
        row.names <- data[[rowvar]]
        data <- data[-rowvar]
        keep <- keep[-rowvar]
      }
    } else if (is.numeric(row.names) && length(row.names) == 1L) {
      compactRN <- FALSE
      rlabp <- row.names
      row.names <- data[[rlabp]]
      data <- data[-rlabp]
      keep <- keep[-rlabp]
    } else stop("invalid 'row.names' specification")
    data <- data[keep]
    
    ## rownames<- is interpreted, so avoid it for efficiency (it will copy)
    if(is.object(row.names) || !(is.integer(row.names)) )
      row.names <- as.character(row.names)
    if(!compactRN) {
      if (length(row.names) != nlines)
        stop("invalid 'row.names' length")
      if (anyDuplicated(row.names))
        stop("duplicate 'row.names' are not allowed")
      if (anyNA(row.names))
        stop("missing values in 'row.names' are not allowed")
    }
    
    ##	this is extremely underhanded
    ##	we should use the constructor function ...
    ##	don't try this at home kids
    
    class(data) <- "data.frame"
    attr(data, "row.names") <- row.names
    data
  }

environment(read.table) <- environment(read.csv)
