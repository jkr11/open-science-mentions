library(RSQLite)
library(dplyr)
conn <- dbConnect(RSQLite::SQLite(), "db/index.db")
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