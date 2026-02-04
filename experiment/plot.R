# load("experiment/mdpi_ed_papers.Rda") # apparently this is called mpdi_ed_papers internally

library(RSQLite)
library(dplyr)
library(metacheck)
library(tidyverse)
library(stringr)

setwd("experiment")

paper_2_df <- function(paper_df, index_df) {
  meta_df <- info_table(paper_df)
  index_df <- index_df %>%
    mutate(id = tools::file_path_sans_ext(basename(tei_local_path)))

  exclude_patterns <- "(?i)editorial|correction|erratum|errata|author statement|retraction|book review|commentary"

  meta_df <- meta_df %>%
    filter(!str_detect(title, exclude_patterns))

  aug_df <- meta_df %>%
    left_join(select(index_df, id, publication_year), by = "id")
  return(aug_df)
}


# use only on non processed papers in xml format.
get_journal_stats <- function(target_journal_id, db_path = "../test_db/index.db") {
  conn_fn <- dbConnect(RSQLite::SQLite(), db_path)
  on.exit(dbDisconnect(conn_fn))

  query <- sprintf("SELECT * FROM works WHERE journal_id = '%s'", target_journal_id)
  index <- dbGetQuery(conn_fn, query)

  if (nrow(index) == 0) {
    stop("No records found for the provided journal_id.")
  }

  index <- index %>% filter(tei_process_status == "DONE")

  index$tei_local_path <- paste0(
    "../test_db/teis/ed/",
    index$tei_local_path
  )

  papers <- metacheck::read(index$tei_local_path)
  save(papers, file = str_glue("{target_journal_id}.Rda"))
  osf_links <- metacheck::osf_links(papers)
  git_links <- metacheck::github_links(papers)
  stats <- paper_2_df(papers, index)

  links <- bind_rows(
    select(osf_links, id),
    select(git_links, id)
  ) %>%
    distinct(id)


  final_result <- links %>%
    left_join(select(stats, id, publication_year), by = "id") %>%
    distinct()

  return(list(final_result, stats))
}

get_download_statistics <- function(target_journal_id) {
  conn <- dbConnect(RSQLite::SQLite(), "../test_db/index.db")
  query <- sprintf("SELECT * FROM works WHERE journal_id = '%s'", target_journal_id)
  index <- dbGetQuery(conn_fn, query)
  failed <- index %>% filter(pdf_download_status != "DONE")
  summary(failed)
  tei_failed <- index %>% filter(tei_process_status != "DONE")
  summary(tei_failed)
  both_failed <- index %>%
    inner_join(tei_failed, by = "openalex_id") %>%
    anti_join(failed, by = "openalex_id")
  summary(both_failed)
  print(both_failed)
}

ds_stats <- get_journal_stats("S4210217710") # Deutsche Schule (Waxmann) 1
ze_stats <- get_journal_stats("S40639335") # Zeitschrift für Erziehungswissenschaft (Springer) 35 # 464
zp_stats <- get_journal_stats("S63113783") # Zeitschrift für Paedagogik (Pedocs) 1
save(ds_stats, file = "ds_stats.Rda")
save(ze_stats, file = "ze_stats.Rda")
save(zp_stats, file = "zp_stats.Rda")

ds_table <- ds_stats[[2]]
print(ds_links)
ds_links <- ds_stats[[1]]
ze_table <- ze_stats[[2]]
ze_links <- ze_stats[[1]]
zp_table <- zp_stats[[2]]
zp_links <- zp_stats[[1]]
zp_table <- zp_table %>% mutate(publication_year = format(as.Date(publication_year, format = "%d.%m.%Y"), "%Y"))

proportion_stats <- function(table_df, links_df) {
  per_year <- table_df %>%
    group_by(publication_year) %>%
    summarise(total_papers = n_distinct(id), .groups = "drop")

  linked_per_year <- links_df %>%
    distinct(id) %>%
    inner_join(select(table_df, id, publication_year), by = "id") %>%
    group_by(publication_year) %>%
    summarise(unique_linked_papers = n_distinct(id), .groups = "drop")

  unique_stats <- per_year %>%
    filter(publication_year != 2026) %>%
    left_join(linked_per_year, by = "publication_year") %>%
    mutate(
      unique_linked_papers = replace_na(unique_linked_papers, 0),
      proportion_linked = unique_linked_papers / total_papers
    )

  return(unique_stats)
}

ds_stats <- proportion_stats(ds_table, ds_links)
print(ds_stats)

ze_stats <- proportion_stats(ze_table, ze_links)
print(ze_stats)

zp_stats <- proportion_stats(zp_table, zp_links)
print(zp_stats)

stats_final <- function(stats) {
  s1 = sum(stats$unique_linked_papers)
  s2 = sum(stats$total_papers)
  return(list(s1,s2,s1/s2))
}



journal_data <- list(dssf, zesf, zpsf)

final_df <- data.frame(
  journal    = c("S4210217710", "S40639335", "S63113783"),
  total      = sapply(journal_data, function(x) x[[2]]),
  link       = sapply(journal_data, function(x) x[[1]]),
  proportion = sapply(journal_data, function(x) x[[3]])
)

print(final_df)

save(final_df, file="de_journals.csv")