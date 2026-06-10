library(metacheck)
library(dplyr)
library(purrr)
library(stringr)

clean_osf_links <- function(link_str) {
  # Force conversion to character to handle factors safely
  link_str <- as.character(link_str)

  if (length(link_str) == 0 || is.na(link_str) || trimws(link_str) == "") {
    return(character(0))
  }

  cleaned <- link_str %>%
    stringr::str_remove_all('["\']') %>%
    stringr::str_split("\\|\\|") %>%
    unlist() %>%
    tolower() %>%
    trimws()

  return(unique(cleaned[cleaned != ""]))
}

analyze_osf_summary <- function(summary) {
  if (is.null(summary) || !is.data.frame(summary) || nrow(summary) == 0) {
    return(tibble(
      osf_status = "failed/empty",
      is_preprint_reg = NA_integer_,
      is_code = NA_integer_,
      is_data = NA_integer_,
      is_supp = NA_integer_,
      pct_code = NA_real_,
      pct_data = NA_real_,
      pct_supp = NA_real_
    ))
  }

  is_preprint_or_reg <- any(summary$registration %in% TRUE) ||
    any(summary$preprint %in% TRUE)

  files <- summary %>% dplyr::filter(osf_type == 'files' & kind == 'file')
  total_files <- nrow(files)

  n_code <- 0
  n_data <- 0
  n_supp <- 0

  if (total_files > 0) {
    n_code <- sum(files$file_category == "code", na.rm = TRUE)
    n_data <- sum(files$file_category == "data", na.rm = TRUE)
    n_supp <- sum(files$file_category == "text", na.rm = TRUE)

    if (n_supp == total_files) {
      is_preprint_or_reg <- TRUE
    }
  }

  pct_code <- if (total_files > 0) (n_code / total_files) * 100 else 0
  pct_data <- if (total_files > 0) (n_data / total_files) * 100 else 0
  pct_supp <- if (total_files > 0) (n_supp / total_files) * 100 else 0

  tibble(
    osf_status = "success",
    is_preprint_reg = as.integer(is_preprint_or_reg),
    is_code = as.integer(n_code > 0),
    is_data = as.integer(n_data > 0),
    is_supp = as.integer(n_supp > 0 && !is_preprint_or_reg),
    pct_code = round(pct_code, 2),
    pct_data = round(pct_data, 2),
    pct_supp = round(pct_supp, 2)
  )
}

process_row_links <- function(raw_link_str) {
  if (is.na(raw_link_str) || trimws(raw_link_str) == "") {
    return(analyze_osf_summary(NULL))
  }

  if (stringr::str_detect(raw_link_str, "(?i)view_only")) {
    return(tibble(
      osf_status = "failed: view_only_link",
      is_preprint_reg = NA_integer_,
      is_code = NA_integer_,
      is_data = NA_integer_,
      is_supp = NA_integer_,
      pct_code = NA_real_,
      pct_data = NA_real_,
      pct_supp = NA_real_
    ))
  }

  if (stringr::str_detect(raw_link_str, "github")) {
    return(tibble(
      osf_status = "failed: github",
      is_preprint_reg = NA_integer_,
      is_code = NA_integer_,
      is_data = NA_integer_,
      is_supp = NA_integer_,
      pct_code = NA_real_,
      pct_data = NA_real_,
      pct_supp = NA_real_
    ))
  }
  # -----------------------------------------------------------------

  cleaned_links <- clean_osf_links(raw_link_str)

  if (length(cleaned_links) == 0) {
    return(analyze_osf_summary(NULL))
  }

  links_df <- tibble(text = cleaned_links)

  tryCatch(
    {
      info <- suppressWarnings(
        osf_retrieve(
          links_df,
          id_col = "text",
          recursive = TRUE,
          find_project = TRUE
        )
      )

      summary_df <- suppressWarnings(
        metacheck::summarize_contents(info)
      )

      Sys.sleep(1.2)
      return(analyze_osf_summary(summary_df))
    },
    error = function(e) {
      return(analyze_osf_summary(NULL))
    }
  )
}

papers <- read.csv('paper1/results/papers_subset.csv', stringsAsFactors = FALSE)

analysis_matrix <- purrr::map_dfr(
  papers$osf_links,
  process_row_links
)

final_papers_df <- dplyr::bind_cols(papers, analysis_matrix)

print(dplyr::filter(final_papers_df, osf_status == "success"))

write.csv(final_papers_df, "test_cat.csv")
