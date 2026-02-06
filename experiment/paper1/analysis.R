library(RSQLite)
library(dplyr)
library(metacheck)
library(tidyverse)
library(stringr)

# replace with own working directory (this is intended to be used from top level)
setwd("/home/jkr/work/open-science/open-science/experiment/paper1")

# "S4210217710" # Deutsche Schule (Waxmann) 1
# "S40639335" # Zeitschrift für Erziehungswissenschaft (Springer)
# "S63113783" # Zeitschrift für Paedagogik (Pedocs) 1

# Run this everytime the db changes
conn <- dbConnect(RSQLite::SQLite(), "../../db/index.db")
query <- "SELECT * FROM works;"
data_all <- dbGetQuery(conn, query)
dbDisconnect(conn)

# manually fix pedocs dates
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
  index_df <- index_df %>%
    mutate(id = tools::file_path_sans_ext(basename(tei_local_path)))

  # filter out non papers
  exclude_patterns <- "(?i)editorial|correction|erratum|errata|author statement|retraction|book review|commentary"

  meta_df <- meta_df %>%
    filter(!str_detect(title, exclude_patterns))

  aug_df <- meta_df %>%
    left_join(select(index_df, id, publication_year), by = "id")
  return(aug_df)
}


# use only on non processed papers in xml format.
get_journal_stats <- function(
  target_journal_id
) {
  index <- data_all %>% filter(journal_id == target_journal_id)

  if (nrow(index) == 0) {
    stop("No records found for the provided journal_id.")
  } else {
    print(nrow(index))
  }

  index <- index %>% filter(tei_process_status == "DONE")

  if (nrow(index) == 0) {
    stop("Convert to TEI first.")
  }

  index$tei_local_path <- paste0(
    "../../db/teis/",
    index$tei_local_path
  )

  # uncomment for new data (!SLOW!)
  #papers <- metacheck::read(index$tei_local_path)
  #save(papers, file = str_glue("{target_journal_id}.Rda"))
  load(str_glue("{target_journal_id}.Rda"))
  osf_links <- metacheck::osf_links(papers)
  git_links <- metacheck::github_links(papers)
  stats <- paper_2_df(papers, index)

  links <- bind_rows(
    osf_links %>% select(id, text) %>% mutate(source_type = "OSF"),
    git_links %>% select(id, text) %>% mutate(source_type = "GitHub")
  ) %>%
    distinct(id, text, .keep_all = TRUE)

  print(links)

  links_by_id <- links %>%
    left_join(select(stats, id, publication_year), by = "id") %>%
    distinct()

  links_by_id <- links_by_id %>%
    group_by(id) %>%
    summarise(
      all_links = list(text),
      link_count = n_distinct(text),
      .groups = "drop"
    )

  stats <- stats %>%
    left_join(links_by_id, by = "id") %>%
    mutate(
      has_link = !is.na(link_count),
      link_count = replace_na(link_count, 0)
    )

  return(stats)
}

ds_stats <- get_journal_stats("S4210217710") # Deutsche Schule (Waxmann) 1
ze_stats <- get_journal_stats("S40639335") # Zeitschrift für Erziehungswissenschaft (Springer) 35 # 464

zp_stats <- get_journal_stats("S63113783") # Zeitschrift für Paedagogik (Pedocs) 1
save(ds_stats, file = "ds_stats.Rda")
save(ze_stats, file = "ze_stats.Rda")
save(zp_stats, file = "zp_stats.Rda")
# load("zp_stats.Rda")
# load("ze_stats.Rda")
# load("ds_stats.Rda"

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
  return(pstats)
}

write.csv(
  download_statistics("S4210217710", ds_stats),
  file = "results/ds_download_statistics.csv",
  quote = FALSE,
  row.names = FALSE
)

write.csv(
  download_statistics("S40639335", ze_stats),
  file = "results/ze_download_statistics.csv",
  quote = FALSE,
  row.names = FALSE
)

write.csv(
  download_statistics("S63113783", zp_stats),
  file = "results/zp_download_statistics.csv",
  quote = FALSE,
  row.names = FALSE
)

print(ze_stats$all_links)

clean_links <- function(link_column) {
  map_chr(
    link_column,
    ~ {
      .x %>%
        str_trim() %>%
        str_to_lower() %>%
        str_remove("^https?://") %>%
        str_remove_all("/+$") %>%
        unique() %>%
        str_c("https://", .) %>%
        paste(collapse = "; ")
    }
  )
}

ze_links_clean <- ze_stats %>%
  filter(has_link) %>%
  mutate(
    doi = paste0("https://link.springer.com/article/", doi),
    all_links = clean_links(all_links)
  ) %>%
  select(doi, all_links)
write_excel_csv(
  ze_links_clean,
  "results/zeitschrift_fuer_erziehungswissenschaften_links_clean.csv",
)

ds_links_clean <- ds_stats %>%
  filter(has_link) %>%
  mutate(
    doi = paste0("https://doi.org/", doi),
    all_links = clean_links(all_links)
  ) %>%
  select(doi, all_links)
write_excel_csv(
  ds_links_clean,
  "results/deutsche_schule_links_clean.csv"
)

zp_links_clean <- zp_stats %>%
  filter(has_link) %>%
  mutate(
    doi = paste0("https://doi.org/", doi),
    all_links = clean_links(all_links)
  ) %>%
  select(doi, all_links)
write_excel_csv(
  zp_links_clean,
  "results/zeitschrift_fuer_paedagogik_links_clean.csv"
)

proportion_stats <- function(stats_df) {
  unique_stats <- stats_df %>%
    filter(publication_year != 2026) %>%
    group_by(publication_year) %>%
    summarise(
      total_papers = n_distinct(id),
      unique_linked_papers = sum(has_link),
      proportion_linked = unique_linked_papers / total_papers,
      .groups = "drop"
    )
  return(unique_stats)
}

ds_unique <- proportion_stats(ds_stats)
print(ds_unique)

ze_unique <- proportion_stats(ze_stats)
print(ze_unique)

zp_unique <- proportion_stats(zp_stats)
print(zp_unique)

stats_final <- function(stats) {
  s1 = sum(stats$unique_linked_papers)
  s2 = sum(stats$total_papers)
  return(list(s1, s2, s1 / s2))
}

dssf <- stats_final(ds_unique)
print(dssf)
zesf <- stats_final(ze_unique)
print(zesf)

library(ggplot2)
library(scales)


plot_stats <- function(stats_df, name) {
  unique_df = proportion_stats(stats_df)

  max_count <- max(unique_df$unique_linked_papers, na.rm = TRUE)
  max_prop <- max(unique_df$proportion_linked, na.rm = TRUE)

  scale_factor <- max_count / (max_prop * 1.1)

  count_breaks <- seq(0, max_count, by = 1)

  ggplot(unique_df, aes(x = publication_year)) +
    geom_col(
      aes(y = unique_linked_papers / scale_factor, fill = "Paper mit Link"),
      alpha = 0.3,
      width = 0.6
    ) +

    geom_line(aes(y = proportion_linked, color = "Anteil"), size = 1) +
    geom_point(aes(y = proportion_linked, color = "Anteil"), size = 3) +

    scale_y_continuous(
      name = "Anteil (Prozent)",
      labels = label_percent(accuracy = 1),
      limits = c(0, max_prop * 1.1),
      sec.axis = sec_axis(
        trans = ~ . * scale_factor,
        name = "Anzahl (Paper mit Link)",
        breaks = count_breaks
      )
    ) +

    scale_x_continuous(breaks = unique_df$publication_year) +
    scale_color_manual(name = "", values = c("Anteil" = "steelblue")) +
    scale_fill_manual(name = "", values = c("Paper mit Link" = "gray70")) +
    labs(
      title = "Anteil der Artikel mit Repositoriums-Links (OSF/GIT)",
      subtitle = str_glue(
        "2017-2025, {name}, N={nrow(stats_df)}"
      ),
      x = "Erscheinungsjahr"
    ) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      axis.title.y.left = element_text(color = "steelblue"),
      axis.title.y.right = element_text(color = "gray40"),
      panel.grid.minor = element_blank()
    )
}

plot_stats(
  ze_stats,
  name = "Zeitschrift für Erziehungswissenschaften (Springer)"
)
ggsave("results/ze.png")
plot_stats(ds_stats, name = "Deutsche Schule (Waxmann)")
ggsave("results/ds.png")
plot_stats(
  zp_stats,
  name = "Zeitschrift für Pädagogik (Beltz/Pedocs)"
)
ggsave("results/zp.png")
