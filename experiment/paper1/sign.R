library(brms)

data <- read.csv("experiment/paper1/checked_links.csv")


model <- brm(
  unique_linked_papers | trials(total_papers) ~ publication_year_centered +
    (1 | journal_long),
  data = data,
  family = binomial()
)

#unique_linked_papers | trials(total_papers) ~
#  publication_year_centered +
#  (publication_year_centered | journal_long)

summary(model)
plot(model)
pp_check(model)
post <- posterior_samples(model)
ggplot(post, aes(x = b_publication_year_centered)) +
  geom_density() +
  labs(title = "Posterior for Year Effect (Centered)")

df <- read.csv(
  "experiment/paper1/checked_links.csv",
  stringsAsFactors = FALSE,
  na.strings = c("", "NA", "NaN", "None")
)
names(df)
head(df, 10)

indicators <- c("is_preprint_reg", "is_code", "is_data", "is_supp")

for (col in indicators) {
  if (!col %in% names(df)) df[[col]] <- NA
}

is_missing <- function(x) {
  s <- as.character(x)
  s_trim <- trimws(tolower(s))
  s_trim %in% c("", "na", "nan", "none") | is.na(x)
}

missing_mat <- sapply(indicators, function(col) is_missing(df[[col]]))
df$failed_audit <- apply(missing_mat, 1, all)

to_logical <- function(x) {
  if (is.logical(x)) {
    return(x)
  }
  s <- tolower(trimws(as.character(x)))
  s[s %in% c("na", "nan", "none", "")] <- NA
  res <- ifelse(
    s %in% c("true", "t", "1"),
    TRUE,
    ifelse(s %in% c("false", "f", "0"), FALSE, NA)
  )
  return(res)
}

has_osf_log <- if ("has_osf" %in% names(df)) {
  to_logical(df$has_osf)
} else {
  rep(NA, nrow(df))
}
has_git_log <- if ("has_git" %in% names(df)) {
  to_logical(df$has_git)
} else {
  rep(NA, nrow(df))
}

second_trial_osf <- ifelse(
  !is.na(has_osf_log) & has_osf_log == FALSE,
  FALSE,
  TRUE
)
second_trial_git <- ifelse(
  !is.na(has_git_log) & has_git_log == FALSE,
  FALSE,
  TRUE
)

second_trial_osf[df$failed_audit == TRUE] <- FALSE
second_trial_git[df$failed_audit == TRUE] <- FALSE

df$second_trial_osf <- second_trial_osf
df$second_trial_git <- second_trial_git

df$has_osf_corrected <- has_osf_log
df$has_git_corrected <- has_git_log
df$has_osf_corrected[df$failed_audit == TRUE] <- FALSE
df$has_git_corrected[df$failed_audit == TRUE] <- FALSE

df$has_osf_corrected <- NULL
df$has_git_corrected <- NULL


collapse_links <- function(x) {
  x_chr <- as.character(x)
  ifelse(
    is.na(x_chr) | x_chr == "",
    NA_character_,
    vapply(
      x_chr,
      function(val) {
        parts <- unlist(strsplit(val, "\\|\\|", perl = TRUE))
        parts <- trimws(parts)
        parts <- parts[parts != ""]
        if (length(parts) == 0) {
          return(NA_character_)
        }
        norm <- tolower(gsub("/+$", "", parts))
        keep <- !duplicated(norm)
        paste(parts[keep], collapse = "||")
      },
      FUN.VALUE = character(1),
      USE.NAMES = FALSE
    )
  )
}

df <- read.csv(
  "experiment/paper1/checked_links_corrected.csv",
  stringsAsFactors = FALSE,
  na.strings = c("", "NA", "None")
)
for (col in c("osf_links", "git_links")) {
  if (col %in% names(df)) df[[col]] <- collapse_links(df[[col]])
}
write.csv(df, "experiment/paper1/checked_links_dedup.csv", row.names = FALSE)
