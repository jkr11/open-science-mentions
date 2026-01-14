library(metacheck)
library(RSQLite)
library(dplyr)
conn <- dbConnect(RSQLite::SQLite(), "test_db/index.db")
df <- dbGetQuery(conn, "select * from works")
head(df, 5)

test_set_teis <- df %>% filter (!is.null(tei_local_path)) %>% filter(journal_id == "S26220619") %>% tibble()
print(test_set_teis)
test_set_teis |> tibble() |> print(n = 30)
avector = as.vector(test_set_teis$tei_local_path)
class(avector)
paper <- metacheck::read(as.vector(test_set_teis$tei_local_path))

print(paper)
print(paper$info)

links <- metacheck::osf_links(paper)


