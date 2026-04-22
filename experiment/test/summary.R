library(RSQLite)

library(dplyr)
conn <- dbConnect(RSQLite::SQLite(), "/home/jere/projects/open-science-mentions/db/index.merged.db")

query <- "SELECT * FROM works;"
df <- dbGetQuery(conn, query)
dbDisconnect(conn)

df %>%
  summarise(
    row_count = n(),
    unique_users = n_distinct(openalex_id),
    unique_journals = n_distinct(journal_id)
  )

df %>% 
  distinct(journal_name)

nums <- df %>%
  group_by(journal_name) %>%
  filter (tei_process_status == "DONE") %>%
  summarise(count = n()) %>%
  arrange(desc(count))

numsp <- df %>%
  group_by(journal_name) %>%
  filter (pdf_download_status == "DONE") %>%
  summarise(count = n()) %>%
  arrange(desc(count))

print(nums)
print(numsp)

library(metacheck)

setwd("~")
setwd("projects/open-science-mentions/experiment/test")

path <- "../../db/teis/a289bbeebfb374cc2271474ec9db286e0f163d081e58e364d76f19b0dfe7fd32.grobid.tei.xml"

if (!file.exists(path)) {
  stop("File does not exist: ", path)
}

obj <- tryCatch(
  readRDS(path),
  error = function(e) stop("Failed to read RDS: ", e$message)
)

print(str(obj, max.level = 1))

links <- tryCatch(
  metacheck::osf_links(obj),
  error = function(e) stop("metacheck::osf_links failed: ", e$message)
)

print(links)


