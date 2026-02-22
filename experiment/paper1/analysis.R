library(tidyverse)
library(ggplot2)
library(metacheck)
library(purrr)

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

ze_links_clean <- ze_stats |>
  filter(has_link) |>
  mutate(
    doi = paste0("https://link.springer.com/article/", doi),
    all_links = clean_links(all_links)
  ) |>
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

write_clean_links(esp_stats, "esp_links_clean")

library(osfr)

# get_osf_files_recursive <- function(entity) {
#   current_level <- osf_ls_files(entity)

#   if (nrow(current_level) == 0) {
#     return(NULL)
#   }

#   files <- osf_ls_files(entity, type = "file")
#   folders <- osf_ls_files(entity, type = "folder")

#   if (nrow(folders) > 0) {
#     sub_files <- map_df(
#       folders$id,
#       ~ {
#         sub_entity <- osf_retrieve_file(.x)
#         get_osf_files_recursive(sub_entity)
#       }
#     )
#     files <- bind_rows(files, sub_files)
#   }

#   return(files)
# }

# probe_osf_files <- function(url) {
#   # Force URL to be a single string and remove whitespace
#   url <- as.character(url[1])
#   url <- gsub("\\s+", "", as.character(url[1]))
#   guid <- str_extract(url, "(?<=osf.io/)[a-z0-9]{5}")

#   if (is.na(guid)) {
#     message(paste("No GUID found in:", url))
#     return(NULL)
#   }

#   tryCatch(
#     {
#       entity <- osf_retrieve_node(guid)
#       files_df <- get_osf_files_recursive(entity)

#       if (nrow(files_df) == 0) {
#         return(NULL)
#       }

#       files_df %>%
#         mutate(
#           extension = tools::file_ext(name),
#         ) %>%
#         select(id, extension, name)
#     },
#     error = function(e) {
#       message(paste("OSF Error for GUID", guid, ":", e$message))
#       return(NULL)
#     }
#   )
# }

# view_file_data <- function(stats) {
#   files <- stats %>%
#     mutate(all_links = clean_links(all_links)) %>%
#     select(doi, all_links)

#   files$file_inventory <- map(
#     files$all_links,
#     ~ map_df(.x, probe_osf_files)
#   )

#   return(files)
# }

# classify_inventory <- function(inventory_df) {
#   if (is.null(inventory_df) || length(inventory_df) == 0) {
#     return("No OSF Data")
#   }
#   exts <- unique(tolower(inventory_df$extension))
#   print(exts)
#   analysis_exts <- c("r", "rmd", "py", "sps", "do", "sas", "jl")
#   data_exts <- c(
#     "csv",
#     "xlsx",
#     "xls",
#     "rds",
#     "dta",
#     "sav",
#     "json",
#     "txt",
#     "tsv"
#   )
#   supp_exts <- c("pdf", "docx", "doc", "html")

#   has_analysis <- any(tolower(exts) %in% analysis_exts)
#   has_data <- any(tolower(exts) %in% data_exts)

#   if (has_analysis && has_data) {
#     return("Both (Analysis + Data)")
#   }
#   if (has_analysis) {
#     return("Analysis Only")
#   }
#   if (has_data) {
#     return("Data Only")
#   }

#   # If it's just PDF/Docs
#   if (any(tolower(exts) %in% supp_exts)) {
#     return("Supplement Only (PDF/Doc)")
#   }

#   return("Other/Unknown")
# }

# epr_summary <- view_file_data(epr_stats)

# epr_summary <- epr_summary %>%
#   mutate(class = map_chr(file_inventory, classify_inventory))

# epr_total <- epr_summary %>%
#   count(class, name = "counts")

print(epr_stats$all_links)

ze_stats_cpy <- ze_stats %>% filter(link_count > 0)
print(ze_stats_cpy)
ze_stats_cpy <- ze_stats_cpy %>%
  mutate(info = map(all_links, ~ osf_retrieve(.x, recursive = TRUE)))

# ze_stats_cpy <- ze_stats_cpy %>%
#   mutate(summary = map(info, ~ summarize_contents(.x)))
#
# test_data <- ze_stats_cpy$info[[2]]
# print(test_data)

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
  proportion_stats(mdpi_stats_2) %>% mutate(Journal = "Education Sciences"),
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
