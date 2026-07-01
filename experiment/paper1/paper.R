library(readr)
library(RSQLite)
library(dplyr)
library(tidyverse)
library(stringr)
library(tidyr)
library(metacheck)

#setwd("experiment/paper1")

file <- "all_papers_data_f.csv"
data <- tryCatch(
  {
    readr::read_delim(
      file,
      delim = ";",
      quote = '"',
      escape_double = TRUE,
      trim_ws = TRUE
    )
  },
  error = function(e) {
    message(
      "read_delim failed: ",
      conditionMessage(e),
      " -- trying base::read.csv fallback"
    )
    tryCatch(
      {
        utils::read.csv(file, stringsAsFactors = FALSE)
      },
      error = function(e2) {
        stop("Failed to read ", file, ": ", conditionMessage(e2))
      }
    )
  }
)

data <- data %>% filter(!is.na(openalex_id) & openalex_id != "")

data <- data %>% filter(rowSums(!is.na(.)) > 1)

data <- data %>%
  mutate(
    has_any_link_num = case_when(
      is.logical(has_any_link) ~ as.integer(has_any_link),
      toupper(as.character(has_any_link)) %in% c("TRUE", "T", "1") ~ 1L,
      toupper(as.character(has_any_link)) %in% c("FALSE", "F", "0") ~ 0L,
      TRUE ~ as.integer(as.numeric(as.character(has_any_link)))
    )
  )

data <- data %>%
  mutate(
    third_trial_has_any_link = as.integer(has_any_link_num)
  ) |>
  filter(publication_year >= 2020, publication_year <= 2025)

data <- data %>%
  mutate(notes2 = as.character(notes2)) %>%
  mutate(
    third_trial_has_any_link = ifelse(
      !is.na(notes2) &
        str_detect(str_to_lower(str_trim(notes2)), "^(raus|not|no)"),
      0L,
      third_trial_has_any_link
    )
  )


data_3 <- read.csv2("data_3_new.csv")

cat("Rows after cleaning:", nrow(data), "\n")
if ("has_any_link_num" %in% names(data)) {
  cat("has_any_link_num distribution:\n")
  print(table(data$has_any_link_num, useNA = "ifany"))
}
cat("third_trial_has_any_link distribution:\n")
print(table(data$third_trial_has_any_link, useNA = "ifany"))
cat("Summary of numeric columns:\n")
print(summary(dplyr::select_if(data, is.numeric)))
