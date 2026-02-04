library(RSQLite)
library(tidyverse)
conn <- dbConnect(RSQLite::SQLite(), "../test_db/index.db")
df <- dbGetQuery(conn, "select * from works")

ed_in_tech <- df %>% filter(journal_id == "S166722454")
print(ed_in_tech %>% filter(pdf_download_status != "DONE"))
