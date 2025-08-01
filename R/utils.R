#' Pipe operator
#'
#' @name %>%
#' @rdname pipe
#' @keywords internal
#' @export
#' @importFrom dplyr %>%
#' @examples
#' x <- 5 %>% sum(10)
#'
#' @usage lhs \%>\% rhs
#' @return return value of rhs function.
NULL


tidy_results <- function(wide_res, features, groups) {
    res <- Reduce(cbind, lapply(wide_res, as.numeric)) %>% data.frame()
    colnames(res) <- names(wide_res)
    res$feature <- rep(features, times = length(groups))
    res$group <- rep(groups, each = length(features))
    res %>% dplyr::select(
        .data$feature,
        .data$group,
        .data$avgExpr,
        .data$logFC,
        .data$statistic,
        .data$auc,
        .data$pval,
        .data$padj,
        .data$pct_in,
        .data$pct_out
    )
}


compute_ustat <- function(Xr, cols, n1n2, group.size) {
    grs <- sumGroups(Xr, cols)

    if (is(Xr, "dgCMatrix")) {
        gnz <- (group.size - nnzeroGroups(Xr, cols))
        zero.ranks <- (nrow(Xr) - diff(Xr@p) + 1) / 2
        ustat <- t((t(gnz) * zero.ranks)) + grs - group.size *
            (group.size + 1 ) / 2
    } else {
        ustat <- grs - group.size * (group.size + 1 ) / 2
    }
    return(ustat)
}


compute_pval <- function(ustat, ties, N, n1n2, alternative) {
    z <- ustat - .5 * n1n2
    CORRECTION <- switch(alternative,
                         "two.sided" = sign(z) * 0.5,
                         "greater" = 0.5,
                         "less" = -0.5)
    .x1 <- N ^ 3 - N
    .x2 <- 1 / (12 * (N^2 - N))
    rhs <- lapply(ties, function(tvals) {
        (.x1 - sum(tvals ^ 3 - tvals)) * .x2
    }) %>% unlist
    usigma <- sqrt(matrix(n1n2, ncol = 1) %*% matrix(rhs, nrow = 1))
    z <- t((z - CORRECTION) / usigma)
    pvals <- switch(alternative,
        "greater" = matrix(stats::pnorm(as.numeric(z), lower.tail = FALSE), ncol = ncol(z)),
        "two.sided" = matrix(2 * stats::pnorm(-abs(as.numeric(z))), ncol = ncol(z)),
        "less" = matrix(stats::pnorm(as.numeric(z), lower.tail = TRUE), ncol = ncol(z))
    )
    return(pvals)
}


#' rank_matrix
#'
#' Utility function to rank columns of matrix
#'
#' @param X feature by observation matrix.
#'
#' @examples
#'
#' data(exprs)
#' rank_res <- rank_matrix(exprs)
#'
#' @return List with 2 items
#' \itemize{
#' \item X_ranked - matrix of entry ranks
#' \item ties - list of tied group sizes
#' }
#' @export
rank_matrix <- function(X) {
    UseMethod("rank_matrix")
}

#' @rdname rank_matrix
#' @export
rank_matrix.dgCMatrix <- function(X) {
    Xr <- Matrix(X, sparse = TRUE)
    ties <- cpp_rank_matrix_dgc(Xr@x, Xr@p, nrow(Xr), ncol(Xr))
    return(list(X_ranked = Xr, ties = ties))
}

#' @rdname rank_matrix
#' @export
rank_matrix.matrix <- function(X) {
    cpp_rank_matrix_dense(X)
}

#' sumGroups
#'
#' Utility function to sum over group labels
#'
#' @param X matrix
#' @param y group labels
#' @param MARGIN whether observations are rows (=2) or columns (=1)
#'
#' @examples
#'
#' data(exprs)
#' data(y)
#' sumGroups_res <- sumGroups(exprs, y, 1)
#' sumGroups_res <- sumGroups(t(exprs), y, 2)
#'
#' @return Matrix of groups by features
#' @export
sumGroups <- function(X, y, MARGIN = 2) {
    if (MARGIN == 2 & nrow(X) != length(y)) {
        stop(
            "nrow(X) != length(y) - the number of rows in the matrix is not
            the same length as group labels"
        )
    } else if (MARGIN == 1 & ncol(X) != length(y)) {
        stop(
            "ncol(X) != length(y) - the number of columns in the matrix is not
             the same length as group labels"
        )
    }
    UseMethod("sumGroups")
}

#' @rdname sumGroups
#' @export
sumGroups.dgCMatrix <- function(X, y, MARGIN = 2) {
    if (MARGIN == 1) {
        cpp_sumGroups_dgc_T(X@x, X@p, X@i, ncol(X), nrow(X), as.integer(y) - 1,
                            length(unique(y)))
    } else {
        cpp_sumGroups_dgc(X@x, X@p, X@i, ncol(X), as.integer(y) - 1,
                        length(unique(y)))
    }
}

#' @rdname sumGroups
#' @export
sumGroups.matrix <- function(X, y, MARGIN = 2) {
    if (MARGIN == 1) {
        cpp_sumGroups_dense_T(X, as.integer(y) - 1, length(unique(y)))
    } else {
        cpp_sumGroups_dense(X, as.integer(y) - 1, length(unique(y)))
    }
}



#' nnzeroGroups
#'
#' Utility function to compute number of zeros-per-feature within group
#'
#' @param X matrix
#' @param y group labels
#' @param MARGIN whether observations are rows (=2) or columns (=1)
#'
#' @examples
#'
#' data(exprs)
#' data(y)
#' nnz_res <- nnzeroGroups(exprs, y, 1)
#' nnz_res <- nnzeroGroups(t(exprs), y, 2)
#'
#' @return Matrix of groups by features
#' @export
nnzeroGroups <- function(X, y, MARGIN = 2) {
    if (MARGIN == 2 & nrow(X) != length(y)) {
        stop("wrong dims")
    } else if (MARGIN == 1 & ncol(X) != length(y)) {
        stop("wrong dims")
    }
    UseMethod("nnzeroGroups")
}

#' @rdname nnzeroGroups
#' @export
nnzeroGroups.dgCMatrix <- function(X, y, MARGIN = 2) {
    if (MARGIN == 1) {
        cpp_nnzeroGroups_dgc_T(X@p, X@i, ncol(X), nrow(X), as.integer(y) - 1,
                            length(unique(y)))
    } else {
        cpp_nnzeroGroups_dgc(X@p, X@i, ncol(X), as.integer(y) - 1,
                            length(unique(y)))
    }
}

#' @rdname nnzeroGroups
#' @export
nnzeroGroups.matrix <- function(X, y, MARGIN = 2) {
    if (MARGIN == 1) {
        cpp_nnzeroGroups_dense_T(X, as.integer(y) - 1, length(unique(y)))
    } else {
        cpp_nnzeroGroups_dense(X, as.integer(y) - 1, length(unique(y)))
    }
}
