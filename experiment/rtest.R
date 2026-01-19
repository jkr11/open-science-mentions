library(metacheck)
library(RSQLite)
library(dplyr)
conn <- dbConnect(RSQLite::SQLite(), "test_db/index.db")
df <- dbGetQuery(conn, "select * from works")
head(df, 5)


df <- df %>% filter(!is.na(pdf_local_path))

sped_teis <- df %>%
  filter(!is.na(tei_local_path)) %>%
  filter(journal_id == "S26220619") %>%
  tibble()
print(sped_teis)
sped_teis |>
  tibble() |>
  print(n = 30)

paper_paths <- "test_db/teis/sped/"

sped_teis$tei_local_path <- paste0(paper_paths, sped_teis$tei_local_path)
paper <- metacheck::read(as.vector(sped_teis$tei_local_path))


print(paper)
print(paper$info)

links <- metacheck::osf_links(paper)
print(links)

# normal_path = "test_db/pdfs/"
frontiers_teis <- df %>%
  filter(journal_id == "S133489141") %>%
  tibble() %>%
  filter(file.exists(pdf_local_path))
print(frontiers_teis)
frontiers_teis <- metacheck::pdf2grobid(frontiers_teis$pdf_local_path)
# frontiers_teis$pdf_local_path <- paste0(normal_path, frontiers_teis$pdf_local_path)
frontiers_papers <- metacheck::read(as.vector(frontiers_teis$pdf_local_path))
print(frontiers_papers)


frontiers_ed_index <- df %>%
  filter(journal_id == "S2596526815") %>%
  tibble() %>%
  filter(tei_process_status == "DONE")
frontiers_ed_index$tei_local_path <- paste0("test_db/teis/ed/", frontiers_ed_index$tei_local_path)
frontiers_ed_papers <- metacheck::read(as.vector(frontiers_ed_index$tei_local_path))

save(frontiers_ed_papers, file = "paperData.Rda")

frontiers_ed_links <- metacheck::osf_links(frontiers_ed_papers)


library(httr2)

library(tidyverse)
library(httr2)
library(purrr)

call_fastapi <- function(path) {
  req <- request("http://127.0.0.1:8000/process") |>
    req_url_query(path = path) |>
    req_retry(max_tries = 3)

  resp <- req_perform(req) |> resp_body_json()

  return(resp$result %||% NA_integer_)
}


df_processed <- frontiers_ed_index |>
  mutate(
    analysis_result = map_int(tei_local_path, call_fastapi)
  )

print(df_processed)

save(df_processed, file="processedFrontiersData.Rda")


# None, 0, 1, 2, 3, 4, 5, 6, 7
# osf link exists
summary(df_processed)
