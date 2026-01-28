library(metacheck)
library(RSQLite)
library(dplyr)
library(ggplot2)

load_object <- function(file) {
  tmp <- new.env()
  load(file = file, envir = tmp)
  tmp[[ls(tmp)[1]]]
}

conn <- dbConnect(RSQLite::SQLite(), "test_db/index.db")
df <- dbGetQuery(conn, "select * from works")
head(df, 5)

cur_db <- df
save(cur_db, file="cur_dvb.Rda")

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
library(purrr)

sped_teis <- sped_teis %>%
  mutate(links = map(tei_local_path, ~{
    p <- metacheck::read(.x)
    metacheck::osf_links(p)
  }))

sped_teis %>% select(tei_local_path, links)

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


conn <- dbConnect(RSQLite::SQLite(), "../test_db/index.db")
df2 <- dbGetQuery(conn, "select * from works")

frontiers_ed_index <- df2 %>%
  filter(journal_id == "S2596526815") %>%
  tibble() %>%
  filter(tei_process_status == "DONE")

frontiers_ed_index$tei_local_path <- paste0("../test_db/teis/ed/", frontiers_ed_index$tei_local_path) # Make sure to only do this once.
frontiers_ed_papers <- metacheck::read(as.vector(frontiers_ed_index$tei_local_path))

save(frontiers_ed_papers, file="frontiers_ed_papers.Rda")

frontiers_ed_index <- frontiers_ed_index %>%
  mutate(id = tools::file_path_sans_ext(basename(tei_local_path)))

print(frontiers_ed_papers)
meta_df <- info_table(frontiers_ed_papers)

save(meta_df, file="meta_df.Rda")

links <- metacheck::osf_links(frontiers_ed_papers)
save(links, file="links.Rda")

git_links <- metacheck::github_links(frontiers_ed_index) %>% filter()

aug_table = meta_df %>%
  left_join(select(frontiers_ed_index, id, publication_year), by = "id")

link_info <- meta_df %>%
  left_join(select(frontiers_ed_index, id, publication_year), by = "id") %>%
  left_join(select(links, id, osf_url = text), by = "id") %>%
  left_join(select(git_links, id, github_url = text), by = "id")

print(link_info %>% filter(!is.na(osf_url) | !is.na(github_url)))

exclude_patterns <- "(?i)editorial|correction|erratum|author statement|retraction|book review|commentary"

aug_table <- aug_table %>%
  filter(!str_detect(title, exclude_patterns))

print(aug_table)

statement_analysis <- aug_table |>
  mutate(
    analysis_result = map_int(
      filename, 
      call_fastapi, 
      .progress = "Analyzing files..."
    )
  )

statement_analysis <- statement_analysis %>% select(id, analysis_result)

# total_statements <- 

library(dplyr)
library(tidyr)
library(ggplot2)

all_linked_ids <- bind_rows(
  select(links, id), 
  select(git_links, id)
) %>%
  distinct(id)

linked_papers_per_year <- all_linked_ids %>%
  inner_join(select(aug_table, id, publication_year), by = "id") %>%
  group_by(publication_year) %>%
  summarise(unique_linked_papers = n(), .groups = "drop")

unique_stats <- total_papers_per_year %>%
  filter(publication_year != 2026) %>%
  left_join(linked_papers_per_year, by = "publication_year") %>%
  mutate(
    unique_linked_papers = replace_na(unique_linked_papers, 0),
    proportion_linked = unique_linked_papers / total_papers
  )


library(patchwork)

p_top <- unique_stats %>%
  ggplot(aes(x = publication_year, y = proportion_linked)) +
  geom_line(color = "#F8766D", linewidth = 1) +
  geom_point(color = "#F8766D") +
  scale_y_continuous(labels = scales::label_percent(accuracy = 0.1)) +
  labs(
    title = "Link Coverage Trends by Year",
    y = "Proportion of total"
  ) +
  theme_classic() +
  theme(
    axis.title.x = element_blank(),
    axis.text.x = element_blank(),
    plot.title = element_text(face = "bold")
  )

p_bottom <- unique_stats %>%
  ggplot(aes(x = publication_year, y = unique_linked_papers)) +
  geom_line(color = "#00BFC4", linewidth = 1) +
  geom_point(color = "#00BFC4") +
  labs(
    x = "Year of Publication",
    y = "Count of papers with >= 1 link"
  ) +
  theme_classic()

combined_plot <- p_top / p_bottom
combined_plot

### MDPI papers 6k

conn <- dbConnect(RSQLite::SQLite(), "../test_db/index.db")
df2 <- dbGetQuery(conn, "select * from works")

mdpi_ed_index <- df2 %>%
  filter(journal_id == "S2738008561") %>%
  tibble() %>%
  filter(pdf_download_status == "DONE")

mdpi_ed_index_tei <- mdpi_ed_index %>% filter(tei_process_status == "DONE")

mdpi_ed_index_tei$tei_local_path <- paste0("../test_db/teis/ed/", mdpi_ed_index_tei$tei_local_path) # Make sure to only do this once.

mdpi_ed_index <- mdpi_ed_index %>%
  mutate(id = tools::file_path_sans_ext(basename(tei_local_path)))

#mpdi_ed_papers = metacheck::read(mdpi_ed_index_tei$tei_local_path)

#save(mpdi_ed_papers, file="mdpi_ed_papers.Rda")

load(file="mdpi_ed_papers.Rda")

mdpi_links <- metacheck::osf_links(mpdi_ed_papers)

mdpi_git_links <- metacheck::github_links(mpdi_ed_papers) %>% filter(!str_detect("github", text))

mdpi_git_links <- mdpi_git_links %>% filter(str_detect(text, "github"))

mdpi_git_links <- head(mdpi_git_links, 64)


mdpi_git_files <- metacheck::github_languages(mdpi_git_links)

res <- lapply(mdpi_git_links, function(x) {
  out <- tryCatch({
    github_languages(x)
  }, error = function(e) {
    return(NULL)
  })
  
  if (!is.null(out) && is.data.frame(out)) {
    out$bytes <- as.numeric(out$bytes)
    out$language <- as.character(out$language)
  }
  
  return(out)
})

mdpi_all_git_links <- dplyr::bind_rows(res)

repo_summary <- mdpi_all_git_links %>%
  summarise()

# erziehunswissenschaften + für pädagogik + deutsche schule

print(repo_summary)

mdpi_meta_df <- info_table(mpdi_ed_papers)

save(mdpi_meta_df, file="mdpi_meta_df.Rda")

mdpi_aug_table = mdpi_meta_df %>%
  left_join(select(mdpi_ed_index, id, publication_year), by = "id")

exclude_patterns <- "(?i)editorial|correction|erratum|author statement|retraction|book review|commentary"

mdpi_aug_table <- mdpi_aug_table %>%
  filter(!str_detect(title, exclude_patterns))

gitlab_links <- function(paper) {
  strip_text <- search_text(paper, ".*[^\\.$]", return = "match", perl = TRUE)
  
  github_regex <- "(?:https?://)?gitlab\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*"
  found_gh <- search_text(strip_text, github_regex, return = "match", perl = TRUE)
  
  no_github_regex <- "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\\.git)?"
  other_gh <- search_text(strip_text, "gitlab") |>
    search_text(github_regex, exclude = TRUE, perl = TRUE) |>
    search_text("gitlab.io", exclude = TRUE) |>
    search_text(no_github_regex, return = "match", perl = TRUE)
  
  all_gh <- dplyr::bind_rows(found_gh, other_gh)
  
  return(all_gh)
}




mdpi_gitlab_links <- gitlab_links(mpdi_ed_papers)
print(mdpi_gitlab_links)


library(dplyr)
library(tidyr)
library(ggplot2)

total_papers_per_year <- mdpi_aug_table %>%
  group_by(publication_year) %>%
  summarise(total_papers = n_distinct(id), .groups = "drop")

all_linked_ids <- bind_rows(
  select(mdpi_links, id), 
  select(mdpi_git_links, id)
) %>%
  distinct(id)

linked_papers_per_year <- all_linked_ids %>%
  inner_join(select(mdpi_aug_table, id, publication_year), by = "id") %>%
  group_by(publication_year) %>%
  summarise(unique_linked_papers = n(), .groups = "drop")

unique_stats <- total_papers_per_year %>%
  filter(publication_year != 2026) %>%
  left_join(linked_papers_per_year, by = "publication_year") %>%
  mutate(
    unique_linked_papers = replace_na(unique_linked_papers, 0),
    proportion_linked = unique_linked_papers / total_papers
  )

library(patchwork)

paper_2_stats <- function(paper_df, index_df) {
  meta_df <- info_table(paper_df)
  index_df %>%
    mutate(id = tools::file_path_sans_ext(basename(tei_local_path)))
  
  exclude_patterns <- "(?i)editorial|correction|erratum|errata|author statement|retraction|book review|commentary"
  
  meta_df <- meta_df %>%
    filter(!str_detect(title, exclude_patterns))
  
  aug_df <- meta_df %>% left_join(select(index_df, id, publication_year), by = "id")
  return(aug_df)
}

test_df <- paper_2_stats(mpdi_ed_papers, mdpi_ed_index)
print(test_df)

title = "MDPI Data availability by Git and Osf links. Total: %s"
title = sprintf(title, length(mpdi_ed_papers))

p_top <- unique_stats %>%
  ggplot(aes(x = publication_year, y = proportion_linked)) +
  geom_line(color = "#F8766D", linewidth = 1) +
  geom_point(color = "#F8766D") +
  scale_y_continuous(labels = scales::label_percent(accuracy = 0.1)) +
  labs(
    title = title,
    y = "Proportion of total"
  ) +
  theme_classic() +
  theme(
    axis.title.x = element_blank(),
    axis.text.x = element_blank(),
    plot.title = element_text(face = "bold")
  )

p_bottom <- unique_stats %>%
  ggplot(aes(x = publication_year, y = unique_linked_papers)) +
  geom_line(color = "#00BFC4", linewidth = 1) +
  geom_point(color = "#00BFC4") +
  labs(
    x = "Year of Publication",
    y = "Count of papers with >= 1 link"
  ) +
  theme_classic()

combined_plot <- p_top / p_bottom
combined_plot

conn_fn <- dbConnect(RSQLite::SQLite(), "../test_db/index.db")
df_fn <- dbGetQuery(conn, "select * from works")
df_fn = df_fn %>% filter(journal_id=="S63113783")
summary(df_fn)

dbDisconnect(conn)
dbDisconnect(conn_fn)


