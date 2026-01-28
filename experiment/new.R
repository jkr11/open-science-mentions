library(dplyr)
library(tidyverse)
library(openalexR)
pedocs1 = read.csv("pedocs-auswahl_1.csv", sep = ";")
pedocs2 = read.csv("pedocs-auswahl_2.csv", sep = ";")
summary(pedocs1)
pedocs = rbind(pedocs1, pedocs2)
# make up a fake id from extern+doi
pedocs = pedocs %>% mutate(openalex_id = paste("extern",Source.Opus))
pedocs$journal_id = "S63113783"

pedocs$journal_name = "ZEITSCHRIFT FUER PAEDAGOGIK"
pedocs_clean = pedocs %>% select(openalex_id, journal_id, journal_name, DOI, Publikationsdatum, Link.pdf.Dateien )


pedocs_clean$pdf_download_status = "PENDING"
pedocs_clean$pdf_local_path = NA
pedocs_clean$tei_process_status = "PENDING"
pedocs_clean$tei_local_path = NA

pedocs_clean$DOI = paste("https://doi.org/", pedocs_clean$DOI, sep="")

pedocs_cpy = pedocs_clean

library(dplyr)
library(openalexR)

id_map <- oa_fetch(
  entity = "works",
  doi = pedocs_clean$DOI,
  verbose = TRUE
) %>%
  select(doi, id)

pedocs_cpy <- pedocs_cpy %>%
  left_join(id_map, by = c("DOI" = "doi"))

pedocs_cpy <- pedocs_cpy %>%
  mutate(openalex_id = if_else(!is.na(id), id, openalex_id))


library(jsonlite)
library(dplyr)

pedocs_cpy <- pedocs_cpy %>%
  rename(oa_urls = Link.pdf.Dateien) %>%
  mutate(oa_urls = sapply(oa_urls, function(x) {
    toJSON(list(pdf_links = x), auto_unbox = FALSE)
  })) %>% 
  mutate(oa_urls = as.character(oa_urls)) %>% # Crucial step for SQL
  select(-id)

pedocs_cpy <- pedocs_cpy %>% rename(doi = DOI) %>% rename(publication_year = Publikationsdatum)

conn_pd <- dbConnect(RSQLite::SQLite(), "../test_db/index.db")
existing_cols <- dbListFields(conn_pd, "works")
match <- all(colnames(pedocs_cpy) %in% existing_cols)
if(!match) {
  stop("Headers do not match the database schema!")
}
pedocs_cpy_clean <- pedocs_cpy %>%
  mutate(across(where(is.list), as.character))

dbWriteTable(conn_pd, "works", pedocs_cpy_clean, append = TRUE, row.names = FALSE)
dbDisconnect(conn_pd)

