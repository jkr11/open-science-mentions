library(tidyverse)
library(httr2)

setwd("experiment/fetch_data")

df <- read.csv("education_journals.csv", sep = ",")

get_oa_stats <- function(journal_id, since_year = NULL) {
  base_url <- "https://api.openalex.org/works"

  filter_str <- paste0("primary_location.source.id:", journal_id)
  if (!is.null(since_year)) {
    filter_str <- paste0(filter_str, ",publication_year:>", since_year)
  }
  filter_str <- paste0(filter_str, "type:article")

  tryCatch(
    {
      data <- request(base_url) %>%
        req_url_query(
          `group_by` = "open_access.is_oa",
          `filter` = filter_str,
          `mailto` = "your_email@example.com"
        ) %>%
        req_perform() %>%
        resp_body_json()

      results <- data$group_by

      noa_count <- keep(results, ~ .x$key == "0") %>% map_int("count") %>% sum()
      oa_count <- keep(results, ~ .x$key == "1") %>% map_int("count") %>% sum()

      return(tibble(oa_count = oa_count, total_count = oa_count + noa_count))
    },
    error = function(e) return(tibble(oa_count = 0, total_count = 0))
  )
}

stats_all <- map_df(df$Journal.ID, ~ get_oa_stats(.x))

stats_recent <- map_df(df$Journal.ID, ~ get_oa_stats(.x, since_year = 2016))

df <- df %>%
  bind_cols(stats_all) %>%
  rename(oa_count_all = oa_count, total_count_all = total_count) %>%
  bind_cols(stats_recent) %>%
  rename(oa_count_recent = oa_count, total_count_recent = total_count) %>%
  mutate(
    oa_proportion_all = ifelse(
      total_count_all > 0,
      oa_count_all / total_count_all,
      0
    ),
    oa_proportion_recent = ifelse(
      total_count_recent > 0,
      oa_count_recent / total_count_recent,
      0
    )
  ) %>%
  mutate(across(contains("proportion"), ~ round(.x, 4)))

print(df)
write.csv(df, file = "education_journals_count.csv", row.names = FALSE)
