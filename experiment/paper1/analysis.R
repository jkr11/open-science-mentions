library(RSQLite)
library(dplyr)
library(metacheck)
library(tidyverse)
library(stringr)
library(scales)

# replace with own working directory (this is intended to be used from top level)
setwd("/home/jere/projects/open-science-mentions/experiment/paper1")

# "S4210217710" # Deutsche Schule (Waxmann) 1
# "S40639335" # Zeitschrift für Erziehungswissenschaft (Springer)
# "S63113783" # Zeitschrift für Paedagogik (Pedocs) 1
# "S2738008561" Education Sciences MDPI

# Run this everytime the db changes
conn <- dbConnect(RSQLite::SQLite(), "../../db/index.db")
query <- "SELECT * FROM works;"
data_all <- dbGetQuery(conn, query)
dbDisconnect(conn)

conn_alt <- dbConnect(RSQLite::SQLite(), "../../test_db/index.db")
data_all <- dbGetQuery(conn_alt, query)
dbDisconnect(conn_alt)

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
  target_journal_id,
  previous_stats = NULL,
  filename = target_journal_id
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
  } else {
    print(nrow(index))
  }

  # If this function was run at a previous time where data_all was not fully populated or new data is now available, use this for an incremental update
  if (!is.null(previous_stats)) {
    print(nrow(previous_stats))
    previous_stats <- previous_stats %>%
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

  if (!is.null(previous_stats)) {
    final_stats <- bind_rows(previous_stats, stats)
    return(final_stats)
  }
  return(stats)
}

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


fe_stats <- get_journal_stats("S2596526815")
save(fe_stats, file = "fe_stats.Rda")

load("fe_stats.Rda")
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

# write.csv(
#   download_statistics("S2738008561", mdpi_stats),
#   file = "results/mdpi_download_statistics.csv",
#   quote = FALSE,
#   row.names = FALSE
# )

write.csv(
  download_statistics("S2738008561", mdpi_stats_2),
  file = "results/mdpi_download_statistics.csv",
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

mdpi_links_clean <- mdpi_stats_2 %>%
  filter(has_link) %>%
  mutate(
    all_links = clean_links(all_links)
  ) %>%
  select(doi, all_links)
write_excel_csv(
  mdpi_links_clean,
  "results/mdpi_links_clean.csv"
)

epr_links_clean <- epr_stats %>%
  filter(has_link) %>%
  mutate(
    all_links = clean_links(all_links)
  ) %>%
  select(doi, all_links)
write_excel_csv(
  epr_links_clean,
  "results/epr_links_clean.csv"
)


write_clean_links <- function(stats, name) {
  clean <- stats %>%
    mutate(
      all_links = clean_links(all_links)
    ) %>%
    select(doi, all_links)
  write_excel_csv(
    clean,
    str_glue("results/{name}.csv")
  )
}
write_clean_links(ethe_stats, "ethe_links_clean")

write_clean_links(fe_stats, "fe_links_clean")

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

mdpi_unique <- proportion_stats(mdpi_stats_2)
print(mdpi_unique)

epr_unique <- proportion_stats(epr_stats)
print(epr_unique)

ethe_unique <- proportion_stats(ethe_stats)
print(ethe_unique)

etre_unique <- proportion_stats(etre_stats)
print(etre_unique)

fe_unique <- proportion_stats(fe_stats)
print(fe_unique)

stats_final <- function(stats) {
  s1 = sum(stats$unique_linked_papers)
  s2 = sum(stats$total_papers)
  return(list(s1, s2, s1 / s2))
}

dssf <- stats_final(ds_unique)
print(dssf)
zesf <- stats_final(ze_unique)
print(zesf)

mdpisf <- stats_final(mdpi_unique)
print(mdpisf)
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
        #breaks = count_breaks
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
plot_stats(
  mdpi_stats_2,
  name = "Education Sciences"
)
ggsave("results/mdpi.png")
plot_stats(epr_stats, name = "Educational Psychology Review")
ggsave("results/epr.png")

plot_stats(ethe_stats, name = "Education Technology in higher Education")
ggsave("results/ethe.png")

plot_stats(etre_stats, name = "Education Technology Research and Developement")
ggsave("results/etre.png")

plot_stats(fe_stats, name = "Frontiers in Education")
ggsave("results/fe.png")

combined_df <- bind_rows(
  proportion_stats(ze_stats) %>%
    mutate(Journal = "Zeitschrift für Erziehungswissenschaften"),
  proportion_stats(ds_stats) %>% mutate(Journal = "Deutsche Schule"),
  proportion_stats(zp_stats) %>% mutate(Journal = "Zeitschrift für Pädagogik"),
  proportion_stats(mdpi_stats_2) %>% mutate(Journal = "Education Sciences"),
  proportion_stats(epr_stats) %>%
    mutate(Journal = "Educational Psychology Review"),
  proportion_stats(ethe_stats) %>%
    mutate(Journal = "Educational Technology in higher Education"),
  proportion_stats(etre_stats) %>%
    mutate(Journal = "Educational Technology Research and Development"),
  proportion_stats(fe_stats) %>%
    mutate(Journal = "Frontiers in Education")
)

combined_df <- combined_df %>%
  group_by(Journal) %>%
  mutate(FigureName = str_glue("{Journal} (N = {sum(total_papers)})")) %>%
  ungroup()

ggplot(
  combined_df,
  aes(x = publication_year, y = proportion_linked, color = Journal)
) +
  geom_line(size = 1) +
  geom_point(size = 3) +
  scale_y_continuous(
    name = "Anteil (Prozent)",
    labels = label_percent(accuracy = 1),
    limits = c(0, max(combined_df$proportion_linked, na.rm = TRUE) * 1.1)
  ) +
  scale_x_continuous(breaks = unique(combined_df$publication_year)) +
  labs(
    title = "Vergleich: Anteil der Artikel mit Repositoriums-Links",
    subtitle = "2017-2025",
    x = "Erscheinungsjahr",
    color = "Journal / Quelle"
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

ggsave("results/combined_stats.png", width = 10, height = 6)

ggplot(
  combined_df,
  aes(
    x = publication_year,
    y = proportion_linked,
    color = str_wrap(FigureName, 20),
  )
) +
  geom_line(linewidth = 1) +
  geom_point(aes(size = unique_linked_papers), shape = 15, alpha = 0.7) +
  scale_size_continuous(
    name = "Anzahl verlinkter Paper",
    range = c(1, 8)
  ) +
  scale_y_continuous(
    name = "Anteil (Prozent)",
    labels = label_percent(accuracy = 1),
    limits = c(0, max(combined_df$proportion_linked, na.rm = TRUE) * 1.1)
  ) +
  scale_x_continuous(breaks = unique(combined_df$publication_year)) +
  labs(
    title = "Vergleich: Anteil der Artikel mit Repositoriums-Links",
    subtitle = "2017-2025",
    x = "Erscheinungsjahr",
    color = "Journal"
  ) +
  scale_fill_brewer(palette = "Pastel2") +
  theme(
    legend.background = element_rect(fill = "white", colour = "black"),
    legend.position = c(0.125, 0.675),
    legend.box = "vertical",
    legend.direction = "vertical",
    panel.grid.minor = element_blank(),
  )
ggsave("results/uebersicht.png", width = 10, height = 8)
# ggsave("results/combined_by_size.png", width = 10, height = 6)

ggplot(
  combined_df,
  aes(
    x = publication_year,
    y = unique_linked_papers,
    fill = str_wrap(FigureName, 20)
  )
) +
  geom_col(color = "white", linewidth = 0.2) +
  scale_y_continuous(
    name = "Anzahl verlinkter Paper",
    limits = c(
      0,
      max(
        aggregate(
          unique_linked_papers ~ publication_year,
          combined_df,
          sum
        )$unique_linked_papers
      ) *
        1.1
    )
  ) +
  scale_x_continuous(breaks = unique(combined_df$publication_year)) +
  labs(
    title = "Vergleich: Anzahl der Artikel mit Repositoriums-Links",
    subtitle = "2017-2025",
    x = "Erscheinungsjahr",
    fill = "Journal"
  ) +
  scale_fill_brewer(palette = "Pastel2") +
  theme_minimal() +
  theme(
    legend.background = element_rect(fill = "white", colour = "black"),
    legend.position = c(0.125, 0.675),
    legend.box = "vertical",
    legend.direction = "vertical",
    panel.grid.minor = element_blank()
  )

ggsave("results/uebersicht_counts.png", width = 10, height = 8)
