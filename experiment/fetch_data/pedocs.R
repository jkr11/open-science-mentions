library(tidyverse)
library(openalexR)
library(jsonlite)
library(RSQLite)
setwd("experiment/fetch_data/")

files <- c("pedocs-auswahl_1.csv", "pedocs-auswahl_2.csv")
pedocs <- map_df(files, ~ read_delim(.x, delim = ";", show_col_types = FALSE))
write.csv(pedocs, file = "pedocs_auswahl.csv", )
# TODO: publication year in pedocs is not really appropriate, use "Erstellungsjahr".

pedocs_clean <- pedocs %>%
  mutate(
    doi = str_glue("https://doi.org{DOI}"),
    journal_id = "S63113783",
    journal_name = "ZEITSCHRIFT FUER PAEDAGOGIK",
    pdf_download_status = "PENDING",
    pdf_local_path = NA_character_,
    tei_process_status = "PENDING",
    tei_local_path = NA_character_
  ) %>%
  rename(
    oa_urls = `Link pdf-Dateien`,
    publication_year = Erstellungsjahr
  ) %>%
  mutate(
    oa_urls = map_chr(
      oa_urls,
      ~ toJSON(list(pdf_links = .x), auto_unbox = FALSE)
    )
  )

id_map <- oa_fetch(
  entity = "works",
  doi = pedocs_clean$DOI,
  verbose = FALSE
) %>%
  select(doi, id)

pedocs_final <- pedocs_clean %>%
  left_join(id_map, by = "doi") %>%
  mutate(
    openalex_id = if_else(!is.na(id), id, paste("extern", `Source-Opus`))
  ) %>%
  select(
    openalex_id,
    journal_id,
    journal_name,
    doi,
    publication_year,
    oa_urls,
    pdf_download_status,
    pdf_local_path,
    tei_process_status,
    tei_local_path #
  )

#update_data <- pedocs_final %>%
#  select(openalex_id, publication_year)

pedocs_final <- pedocs_final %>%
  mutate(
    publication_year = format(
      as.Date(publication_year, format = "%d.%m.%Y"),
      "%Y"
    )
  )

conn_pd <- dbConnect(RSQLite::SQLite(), "../../db/index.db")
#
# dbWriteTable(
#   conn_pd,
#   "temp_year_update",
#   update_data,
#   overwrite = TRUE,
#   temporary = TRUE
# )
#
# dbExecute(
#   conn_pd,
#   "
#   UPDATE works
#   SET publication_year = (
#     SELECT temp_year_update.publication_year
#     FROM temp_year_update
#     WHERE temp_year_update.openalex_id = works.openalex_id
#   )
#   WHERE EXISTS (
#     SELECT 1
#     FROM temp_year_update
#     WHERE temp_year_update.openalex_id = works.openalex_id
#   )
# "
# )
# dbExecute(conn_pd, "DROP TABLE temp_year_update")
# dbDisconnect(conn_pd)

existing_cols <- dbListFields(conn_pd, "works")
missing_cols <- setdiff(colnames(pedocs_final), existing_cols)

if (length(missing_cols) > 0) {
  dbDisconnect(conn_pd)
  stop(paste(
    "The following columns are missing from the DB:",
    paste(missing_cols, collapse = ", ")
  ))
}

dbBegin(conn_pd)
tryCatch(
  {
    dbWriteTable(
      conn_pd,
      "works",
      pedocs_final,
      append = TRUE,
      row.names = FALSE
    )
    dbCommit(conn_pd)
    message("Database update successful.")
  },
  error = function(e) {
    dbRollback(conn_pd)
    message("Error: Database write failed. Rolling back changes.")
    message(e)
  }
)

dbDisconnect(conn_pd)
