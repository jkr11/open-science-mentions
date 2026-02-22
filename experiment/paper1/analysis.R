library(tidyverse)
library(ggplot2)
library(metacheck)
library(purrr)
library(dplyr)
library(readr)
library(stringr)

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
    has_osf = map_lgl(osf_links_obj, ~ length(.x) > 0),
    has_git = map_lgl(git_links_obj, ~ length(.x) > 0)
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
    all_git_links = map(git_links_obj, scrub_links)
  )

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


ze_stats_cpy <- ze_stats %>% filter(link_count > 0)
print(ze_stats_cpy)
ze_stats_cpy <- ze_stats_cpy %>%
  mutate(info = map(all_links, ~ osf_retrieve(.x, recursive = TRUE)))


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

esp_unique <- proportion_stats(esp_stats)
print(esp_unique)


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


theme_set(
  theme_classic() +
    theme(text = element_text(family = "Courier"))
)


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

plot_stats(esp_stats, name = "Empirische Sonderpaedagogik")
ggsave("results/esp.png")
combined_df <- bind_rows(
  proportion_stats(ze_stats) %>%
    mutate(Journal = "Zeitschrift für Erziehungswissenschaften"),
  proportion_stats(ds_stats) %>% mutate(Journal = "Deutsche Schule"),
  proportion_stats(zp_stats) %>% mutate(Journal = "Zeitschrift für Pädagogik"),
  proportion_stats(mdpi_stats) %>% mutate(Journal = "Education Sciences"),
  proportion_stats(epr_stats) %>%
    mutate(Journal = "Educational Psychology Review"),
  proportion_stats(ethe_stats) %>%
    mutate(Journal = "Educational Technology in higher Education"),
  proportion_stats(etre_stats) %>%
    mutate(Journal = "Educational Technology Research and Development"),
  proportion_stats(fe_stats) %>%
    mutate(Journal = "Frontiers in Education"),
  proportion_stats(esp_stats) %>%
    mutate(Journal = "Empirische Sonderpädagogik")
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
    subtitle = str_glue("2017-2025, N = {sum(combined_df$total_papers)}"),
    x = "Erscheinungsjahr",
    fill = "Journal"
  ) +
  # scale_fill_brewer(palette = "Pastel2") +
  theme(
    legend.background = element_rect(fill = "white", colour = "black"),
    legend.position = c(0.125, 0.675),
    legend.box = "vertical",
    legend.direction = "vertical",
    panel.grid.minor = element_blank()
  )

ggsave("results/uebersicht_counts.png", width = 10, height = 8)
