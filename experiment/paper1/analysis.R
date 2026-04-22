library(DBI)
library(RSQLite)
library(tidyverse)
library(ggplot2)
library(purrr)
library(dplyr)
library(readr)
library(stringr)
library(nlme)
library(scales)

setwd("experiment/paper1")

conn <- dbConnect(RSQLite::SQLite(), "../../db/index.merged.db")
works <- dbGetQuery(conn, "SELECT * FROM works")
paper_links <- dbGetQuery(conn, "SELECT openalex_id, osf_links, git_links FROM paper_links")
dbDisconnect(conn)

journal_map <- tribble(
  ~short , ~id           , ~full_name                                        ,
  "ds"   , "S4210217710" , "Deutsche Schule"                                 ,
  "ze"   , "S40639335"   , "Zeitschrift für Erziehungswissenschaften"        ,
  "zp"   , "S63113783"   , "Zeitschrift für Pädagogik"                       ,
  "mdpi" , "S2738008561" , "Education Sciences"                              ,
  "epr"  , "S187318745"  , "Educational Psychology Review"                   ,
  "ethe" , "S4210201537" , "Educational Technology in Higher Education"      ,
  "etre" , "S114840262"  , "Educational Technology Research and Development" ,
  "fe"   , "S2596526815" , "Frontiers in Education"                          ,
  "esp"  , "S4306509262" , "Empirische Sonderpädagogik"                      ,
  "cog"  , "S2764918247" , "COGENT EDUCATION"                                ,
  "flr"  , "S4210191100" , "Frontline Learning Research"                     ,
  "aero" , "S2738252563" , "AERA Open"                                      
)

reg <- journal_map |>
  select(id, journal_short = short, journal_long = full_name)

parse_link_column <- function(link_text) {
  if (is.na(link_text) || !nzchar(link_text)) {
    return(character(0))
  }
  strsplit(link_text, "\\|\\|")[[1]]
}

index_with_links <- works |>
  left_join(reg, by = c("journal_id" = "id")) |>
  left_join(paper_links, by = "openalex_id") |>
  mutate(
    osf_links_raw = map(osf_links, parse_link_column),
    git_links_raw = map(git_links, parse_link_column),
    has_osf = map_lgl(osf_links_raw, ~ length(.x) > 0),
    has_git = map_lgl(git_links_raw, ~ length(.x) > 0)
  ) |>
  mutate(
    all_osf_links = map_chr(osf_links_raw, ~ paste(.x, collapse = "; ")),
    all_git_links = map_chr(git_links_raw, ~ paste(.x, collapse = "; ")),
    has_any_link = has_osf | has_git
  )

print(index_with_links %>% count(journal_short, publication_year, has_any_link))

# Prepare links for analysis - split by || delimiter and clean
clean_links <- function(link_text) {
  if (is.na(link_text) || !nzchar(link_text)) {
    return(NA_character_)
  }
  link_text |>
    str_trim() |>
    str_to_lower() |>
    str_remove("^https?://") |>
    str_remove_all("/+$") |>
    unique() |>
    paste(collapse = "; ")
}

index_with_links <- index_with_links |>
  mutate(
    all_osf_links_clean = map_chr(all_osf_links, clean_links),
    all_git_links_clean = map_chr(all_git_links, clean_links)
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

theme_set(
  theme_classic() +
    theme(text = element_text(family = "Courier"))
)

calc_combined_proportions <- function(master_df) {
  master_df |>
    filter(publication_year != 2026) |>
    filter(publication_year > 2019) |>
    mutate(
      has_any_link = has_osf | has_git
    ) |>
    group_by(journal_long, publication_year) |>
    summarise(
      total_papers = n_distinct(openalex_id),
      unique_linked_papers = sum(
        has_any_link,
        na.rm = TRUE
      ),
      proportion_linked = unique_linked_papers / total_papers,
      .groups = "drop"
    ) |>
    group_by(journal_long) |>
    mutate(
      FigureName = str_glue("{journal_long} (N = {sum(total_papers)})")
    ) |>
    ungroup()
}

combined_df <- calc_combined_proportions(
  index_with_links
)

fit <- lme(
  fixed = log(proportion_linked + 0.001) ~ publication_year,
  random = ~ publication_year | journal_long,
  data = combined_df,
  #weights = varFixed(~ I(1 / total_papers))
)
summary(fit)

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
    subtitle = str_glue("2017-2025"),
    x = "Erscheinungsjahr",
    color = "Journal"
  ) +
  scale_fill_brewer(palette = "Pastel2") +
  theme(
    legend.background = element_rect(fill = "white", colour = "black"),
    legend.position = c(0.125, 0.575),
    legend.box = "vertical",
    legend.direction = "vertical",
    panel.grid.minor = element_blank(),
  )
ggsave("results/uebersicht.png", width = 10, height = 8)

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
    subtitle = str_glue("2017-2025, N = {sum(combined_df$total_papers)}"),
    x = "Erscheinungsjahr",
    fill = "Journal"
  ) +
  theme(
    legend.background = element_rect(fill = "white", colour = "black"),
    legend.position = c(0.125, 0.675),
    legend.box = "vertical",
    legend.direction = "vertical",
    panel.grid.minor = element_blank()
  )

ggsave("results/uebersicht_counts.png", width = 10, height = 8)

# id, journal, year, has_osf, has_git, has_any_link, ()
