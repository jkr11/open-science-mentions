library(RSQLite)
library(dplyr)
library(tidyverse)
library(stringr)
library(here)
library(tidyr)
library(metacheck)

# Use this when running from toplevel
setwd("experiment/paper1")

# TODO: save this as a csv
# Run this everytime the db changes
# conn <- dbConnect(RSQLite::SQLite(), "../../db/index.db")
# query <- "SELECT * FROM works;"return
# data_all <- dbGetQuery(conn, query)
# dbDisconnect(conn)

# save(data_all, file = "data/index.Rda")
load(file = "data/index.Rda") # TODO: change to Rds?

data <- data_all |>
  mutate(doi = str_remove(doi, "^https?://(dx\\.)?doi\\.org/")) |>
  mutate(doi = str_remove(doi, "^https?://(dx\\.)?doi\\.org")) |>
  mutate(tei_id = tei_local_path) |>
  mutate(tei_local_path = paste0("../../db/teis/", tei_local_path))


journal_map <- tribble(
  ~short , ~id           , ~full_name                                        ,
  "ds"   , "S4210217710" , "Deutsche Schule"                                 ,
  "ze"   , "S40639335"   , "Zeitschrift für Erziehungswissenschaften"        ,
  "zp"   , "S63113783"   , "Zeitschrift für Pädagogik"                       ,
  "mdpi" , "S2738008561" , "Education Sciences"                              ,
  "epr"  , "S187318745"  , "Educational Psychology Review"                   ,
  "ethe" , "S4210201537" , "Educational Technology in Higher Education"      ,
  "etre" , "S114840262"  , "Educational Technology Research and Development" ,
  "fe"   , "S2596526815" , "Frontiers in Education"                          ,
  "esp"  , "S4306509262" , "Empirische Sonderpädagogik"
)

reg <- journal_map |>
  select(id, journal_short = short, journal_long = full_name)

data <- data |> left_join(reg, by = c("journal_id" = "id"))


paper_2_df <- function(paper_df, index_df) {
  meta_df <- info_table(paper_df)
  index_df <- index_df |>
    mutate(id = tools::file_path_sans_ext(basename(tei_local_path)))

  # filter out non papers
  exclude_patterns <- "(?i)editorial|correction|erratum|errata|author statement|retraction|book review|commentary"

  meta_df <- meta_df |>
    filter(!str_detect(title, exclude_patterns))

  aug_df <- meta_df |>
    left_join(select(index_df, id, publication_year), by = "id")

  aug_df
}
# use only on non processed papers in xml format.
get_journal_stats <- function(
  target_journal_id,
  previous_stats = NULL,
  filename = target_journal_id
) {
  index <- data_all |> filter(journal_id == target_journal_id)

  if (nrow(index) == 0) {
    stop("No records found for the provided journal_id.")
  } else {
    print(nrow(index))
  }

  index <- index |> filter(tei_process_status == "DONE")

  if (nrow(index) == 0) {
    stop("Convert to TEI first.")
  } else {
    print(nrow(index))
  }

  # If this function was run at a previous time where data_all was not fully populated or new data is now available, use this for an incremental update
  if (!is.null(previous_stats)) {
    print(nrow(previous_stats))
    previous_stats <- previous_stats |>
      mutate(doi = paste0("https://doi.org/", doi))
    index <- index %>% anti_join(previous_stats, by = "doi")

    if (nrow(index) == 0) {
      message("No new records to process.")
      return(previous_stats)
    }
    print(paste("Processing", nrow(index), "new records..."))
  } else {
    print(nrow(index))
  }

  save_name = str_glue("{filename}.Rda")

  index$tei_local_path <- paste0(
    "../../db/teis/",
    index$tei_local_path
  )

  # uncomment for new data (!SLOW!)
  # papers <- metacheck::read(index$tei_local_path)
  # save(papers, file = save_name)

  load(save_name)

  osf_links <- metacheck::osf_links(papers)
  git_links <- metacheck::github_links(papers)
  stats <- paper_2_df(papers, index)

  index <- index %>% left_join()

  links <- bind_rows(
    osf_links |> select(id, text) |> mutate(source_type = "OSF"),
    git_links |> select(id, text) |> mutate(source_type = "GitHub")
  ) |>
    distinct(id, text, .keep_all = TRUE)

  print(links)

  links_by_id <- links |>
    left_join(select(stats, id, publication_year), by = "id") |>
    distinct()

  links_by_id <- links_by_id |>
    group_by(id) |>
    summarise(
      all_links = list(text),
      link_count = n_distinct(text),
      .groups = "drop"
    )

  stats <- stats |>
    left_join(links_by_id, by = "id") |>
    mutate(
      has_link = !is.na(link_count),
      link_count = replace_na(link_count, 0)
    )

  if (!is.null(previous_stats)) {
    final_stats <- bind_rows(previous_stats, stats)
    return(final_stats)
  }
  return(stats)
}

journal_batches <- data |>
  filter(!journal_short %in% c("fe", "mdpi")) |>
  group_split(journal_id)

processed_batches <- map(journal_batches, function(batch_data) {
  current_id <- unique(batch_data$journal_id)
  save_path <- paste0("data/journal_batches/data_", current_id, ".rds")

  if (file.exists(save_path)) {
    return(readRDS(save_path))
  }

  processed_batch <- batch_data |>
    mutate(
      paper_obj = map(
        tei_local_path,
        possibly(metacheck::read, otherwise = NULL)
      )
    )
  saveRDS(processed_batch, file = save_path)
  return(processed_batch)
})
print(processed_batches)
batches <- bind_rows(processed_batches) |> select(openalex_id, paper_obj)

data <- data |>
  left_join(batches, by = "openalex_id")

#' Counts how many papers were actually processed. Note this only works if you have the full database.
download_statistics <- function(id, stats_df) {
  data_loc <- data_all %>%
    filter(journal_id == id, publication_year != 2026)
  pstats <- data_loc %>%
    summarise(
      total_records = n(),
      pdfs_downloaded = sum(pdf_download_status == "DONE", na.rm = TRUE),
      pdf_download_rate = pdfs_downloaded / total_records,

      tei_processed = sum(tei_process_status == "DONE", na.rm = TRUE),
      tei_success_rate = tei_processed / total_records,

      actually_handled = nrow(stats_df)
    )
  pstats
}

write.csv(
  download_statistics("S4210217710", ds_stats),
  file = "results/ds_download_statistics.csv",
  quote = FALSE,
  row.names = FALSE
)

saveRDS(data, file = "data/data_with_journals.rds")
