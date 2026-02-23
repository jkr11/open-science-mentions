library(tidyverse)
library(ggplot2)
library(metacheck)
library(purrr)
library(dplyr)
library(readr)
library(stringr)
library(nlme)
library(scales)

setwd("experiment/paper1")

index <- readRDS(file = "data/data_with_journals.rds")

# Add in links from github and osf
index_with_links <- index |>
  mutate(
    osf_links_obj = map(
      paper_obj,
      possibly(~ metacheck::osf_links(.x), otherwise = NULL)
    ),
    git_links_obj = map(
      paper_obj,
      possibly(~ metacheck::github_links(.x), otherwise = NULL)
    ),
    has_osf = map_lgl(osf_links_obj, ~ !is.null(.x) && nrow(.x) > 0),
    has_git = map_lgl(git_links_obj, ~ !is.null(.x) && nrow(.x) > 0)
  )


scrub_links <- function(lt) {
  if (is.null(lt) || (is.data.frame(lt) && nrow(lt) == 0)) {
    return(character(0))
  }

  lt %>%
    pull(text) %>%
    str_remove_all("\\s+") %>%
    tolower() %>%
    unique()
}

index_with_links <- index_with_links |>
  mutate(
    all_osf_links = map(osf_links_obj, scrub_links),
    all_git_links = map(git_links_obj, scrub_links),
    has_any_link = has_osf | has_git
  )

index_with_links <- index_with_links |>
  filter(journal_short != "mdpi") |>
  filter(publication_year > 2016)

clean_links <- function(link_column) {
  map_chr(
    link_column,
    ~ {
      .x |>
        str_trim() |>
        str_to_lower() |>
        str_remove("^https?://") |>
        str_remove_all("/+$") |>
        unique() |>
        str_c("https://", .) |>
        paste(collapse = "; ")
    }
  )
}

safe_retrieve <- possibly(metacheck::osf_retrieve, otherwise = NULL)

# OSF Token is needed here
# TODO: api doesnt fully complete here, rerun this where Failed.
index_with_links <- index_with_links |>
  mutate(
    info = map2(
      all_osf_links,
      has_osf,
      ~ if (.y) safe_retrieve(.x, recursive = TRUE) else NULL
    )
  )

index_with_links <- index_with_links |>
  mutate(
    temp_content = map(
      info,
      function(x) {
        if (is.null(x) || identical(x, "Fail")) {
          return(tibble(has_data = FALSE, has_code = FALSE, has_supp = FALSE))
        }
        if (!is.data.frame(x) || nrow(x) == 0) {
          return(tibble(has_data = FALSE, has_code = FALSE, has_supp = FALSE))
        }
        all_types <- tolower(paste(
          tidyr::replace_na(x$filetype, ""),
          collapse = " "
        ))
        tibble(
          has_data = str_detect(all_types, "data"),
          has_code = str_detect(all_types, "code|syntax|script"),
          has_supp = str_detect(all_types, "text|video|web")
        )
      }
    )
  ) |>
  unnest(temp_content)


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
    filter(publication_year != 2016) |>
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
