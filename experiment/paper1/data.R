library(RSQLite)
library(dplyr)
library(tidyverse)
library(stringr)
library(here)


# Use this when running from toplevel
# setwd("experiment/paper1")

# "S4210217710" # Deutsche Schule (Waxmann) 1
# "S40639335" # Zeitschrift für Erziehungswissenschaft (Springer)
# "S63113783" # Zeitschrift für Paedagogik (Pedocs) 1
# "S2738008561" Education Sciences MDPI
# "S4306509262", # Empirische Sonderpädagogik

# Run this everytime the db changes
# conn <- dbConnect(RSQLite::SQLite(), "../../db/index.db")
# query <- "SELECT * FROM works;"return
# data_all <- dbGetQuery(conn, query)
# dbDisconnect(conn)

# save(data_all, file = "index.Rda")
load(file = "data/index.Rda")

data <- data_all |>
  mutate(doi = str_remove(doi, "^https?://(dx\\.)?doi\\.org/")) |>
  mutate(doi = str_remove(doi, "^https?://(dx\\.)?doi\\.org"))

# manually fix pedocs dates (TODO: retire to branch)
# data_all <- data_all %>%
#   mutate(
#     publication_year = case_when(
#       journal_id == "S63113783" ~ format(
#         as.Date(publication_year, format = "%d.%m.%Y"),
#         "%Y"
#       ),
#       TRUE ~ as.character(publication_year)
#     )
#   )

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

# TODO: replace this with the lists from fetch_data
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

selection <- c("ze", "ds")

selected_journals <- journal_map %>%
  filter(short %in% selection)

force_recompute <- FALSE

pwalk(selected_journals, function(short, id, full_name) {
  var_name <- paste0(short, "_stats")
  file_path <- paste0("data/", paste0(var_name, ".Rda"))
  print(file_path)
  should_compute <- force_recompute || !file.exists(file_path)

  if (should_compute) {
    message(sprintf("Computing/Downloading stats for: %s...", full_name))

    stats_data <- get_journal_stats(id)

    assign(var_name, stats_data, envir = .GlobalEnv)
    save(list = var_name, file = file_path)
  } else {
    message(sprintf("Loading existing file for: %s", short))
    load(file_path, envir = .GlobalEnv)
  }
})

# Given the way we download, we process papers in journal batches. Loading these into metacheck takes a long time so we save and reload them here only on changes

# ds_stats <- get_journal_stats("S4210217710") # Deutsche Schule (Waxmann) 1
# ze_stats <- get_journal_stats("S40639335") # Zeitschrift für Erziehungswissenschaft (Springer) 35 # 464
#
# zp_stats <- get_journal_stats("S63113783") # Zeitschrift für Paedagogik (Pedocs) 1
# save(ds_stats, file = "ds_stats.Rda")
# save(ze_stats, file = "ze_stats.Rda")
# save(zp_stats, file = "zp_stats.Rda")
load("zp_stats.Rda")
load("ze_stats.Rda")
load("ds_stats.Rda")

#mdpi_stats <- get_journal_stats("S2738008561")
#save(mdpi_stats, file = "mdpi_stats.Rda")
load(file = "mdpi_stats.Rda")


# mdpi_stats_2 <- get_journal_stats(
#   "S2738008561",
#   previous_stats = mdpi_stats,
#   filename = "S2738008561_2"
# )
# save(mdpi_stats_2, file = "mdpi_stats_2.Rda")
load(file = "mdpi_stats_2.Rda")

mdpi_stats_3 <- mdpi_stats
save(mdpi_stats_3, file = "mdpi_stats_3.Rda")

mdpi_stats <- mdpi_stats_2
save(mdpi_stats, file = "mdpi_stats.Rda")

#zg_stats <- get_journal_stats("S4210233694")
#save(zg_stats, file = "zg_stats.Rda")
load("zg_stats.Rda")
#epr_stats <- get_journal_stats("S187318745") # Educational Psychology Review
#save(epr_stats, file = "epr_stats.Rda")
load("epr_stats.Rda")
# ethe_stats <- get_journal_stats("S4210201537")
# save(ethe_stats, file = "ethe_stats.Rda")

load("ethe_stats.Rda")

# etre_stats <- get_journal_stats("S114840262")
# save(etre_stats, file = "etre_stats.Rda")
load("etre_stats.Rda")


# fe_stats <- get_journal_stats("S2596526815")
# save(fe_stats, file = "fe_stats.Rda")

load("fe_stats.Rda")

# esp_stats <- get_journal_stats("S4306509262")
# save(esp_stats, file = "esp_stats.Rda")

load("esp_stats.Rda")


# How many paper were actually processed?
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
