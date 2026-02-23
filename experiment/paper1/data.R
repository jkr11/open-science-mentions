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
# saveRDS(data_all, "data/index.Rds")

data_all <- readRDS(file = "data/index.Rds")
# some of the doi links were wrong in the db.
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

saveRDS(data, file = "data/data_with_journals.rds")
