################################################################################
#
# Title: Open Science in Education
#
# Contact: XXX
#
# Last changes: 01.06.2026
#
################################################################################

# 1. Environment ---------------------------------------------------------------

library(tidyverse) # Data Wrangling
library(rcartocolor) # Colors
library(patchwork)


data_original <- read.csv2("all_papers_data.csv") |>
  mutate(across(
    where(is.character), # Unify data format
    ~ iconv(.x, from = "", to = "UTF-8", sub = "")
  ))

# 2. Descriptive Statistics ----------------------------------------------------

data_1 <- data_original |>
  filter(has_any_link == T) |>
  select(
    -oa_urls,
    -pdf_download_status,
    -pdf_local_path,
    -tei_process_status,
    -tei_local_path,
    -journal_short,
    -journal_long,
    -osf_links,
    -git_links,
    -osf_links_raw,
    -git_links_raw,
    -all_osf_links,
    -all_git_links,
    -has_any_link,
    -all_osf_links_clean,
    -all_git_links_clean
  ) |>
  mutate(across(everything(), ~ na_if(as.character(.x), ""))) |>
  mutate(across(everything(), ~ na_if(as.character(.x), "X"))) |>
  filter(is.na(notes2) | !str_starts(notes2, "raus"))

write.csv2(data_1, "data_with_links.csv")

# 3. Categories ----------------------------------------------------------------

## 3.1 Iterations of ChatGPT model 5.5 thinking ----

data_2 <- list.files(
  # Read all iterations
  "ChatGPT Coding/Kategorisierung",
  pattern = ".csv",
  full.names = TRUE
) |>
  set_names(basename) |>
  map(read.csv) |>
  list_rbind(names_to = "iteration") |>
  pivot_longer(cols = C1:C14, names_to = "Category", values_to = "Code") |>
  # Which categories were rated most?
  count(Article_ID, Category, wt = Code, name = "Rating") |>
  # Only >= 70% IRR
  filter(Rating > 6)

## 3.2 Distribution of Categories ----

plot1 <- data_2 |>
  count(Category) |>
  mutate(
    Category = recode(
      Category,
      "C1" = "EdTech & AI",
      "C2" = "STEM Education",
      "C3" = "Higher Education",
      "C4" = "Assessment",
      "C5" = "Learning Psychology",
      "C6" = "Teacher Education",
      "C7" = "Inclusion & Diversity",
      "C8" = "Digital Learning",
      "C9" = "Curriculum & Instruction",
      "C10" = "Open Science",
      "C11" = "Policy & Systems",
      "C12" = "Literacy & Language",
      "C13" = "Informal Learning",
      "C14" = "Child Development"
    )
  ) |>
  # Barplot of Categories
  ggplot(aes(y = reorder(Category, n), x = n)) +
  geom_col(position = "dodge", alpha = 0.8) +
  labs(x = "Number of Papers", y = "Categories") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.01))) +
  theme_bw()

ggsave("figure_1.pdf", plot1, width = 20, height = 8, units = "cm")

## 3.3 Recherche Results ----

table(data_original$has_any_link)
table(data_original$notes2)

table(data_original$journal_name) / 17586 * 100
table(data_1$journal_name)

table(data_2$Category)

table(data_1$country)

## 3.4 Longtern Development ----

plot2 <-
  data_1 %>%
  select(openalex_id, journal_name, publication_year) %>%
  count(journal_name, publication_year) %>%
  mutate(publication_year = as.numeric(publication_year)) %>%
  filter(publication_year < 2026) %>%
  filter(journal_name != "SAGE Open") %>%
  mutate(
    journal_name = case_when(
      journal_name ==
        "International Journal of Educational Technology in Higher Education" ~ "IJETHE",
      TRUE ~ journal_name
    )
  ) %>%
  ggplot(aes(x = publication_year, y = n)) +
  geom_point() +
  geom_line() +
  facet_wrap(~journal_name) +
  theme_bw() +
  theme(legend.position = "bottom") +
  labs(y = "Number of Papers", x = "Publication Year")

plot2

ggsave("figure_2.pdf", plot2, width = 20, height = 10, units = "cm")

## 3.5 Methodical analysis ----

data_3 <- data_1 %>%
  mutate(
    study_type = case_when(
      notes2 == "review" ~ "review",
      method_quanti == 1 & method_quali == 0 ~ "quantitative",
      method_quanti == 0 & method_quali == 1 ~ "qualitative",
      method_quanti == 1 & method_quali == 1 ~ "mixed"
    )
  )

write.csv2(data_3, "data_3.csv") # Manual coding of NAs

data_3 <- read.csv2("data/data_3_new.csv") %>%
  select(
    openalex_id,
    study_type,
    open_data,
    open_code,
    open_material,
    open_analysis,
    prerig
  ) %>%
  mutate(across(everything(), ~ replace_na(.x, 0))) %>%
  pivot_longer(
    cols = c(open_data, open_code, open_material, open_analysis, prerig),
    names_to = "open_category",
    values_to = "available"
  ) %>%
  group_by(study_type, open_category) %>%
  summarise(
    n_total = n(),
    n_available = sum(available == 1, na.rm = TRUE),
    percent = n_available / n_total * 100,
    .groups = "drop"
  ) %>%
  mutate(Perc_total = n_total / 250 * 100) %>%
  mutate(
    open_category = factor(
      open_category,
      levels = c(
        "prerig",
        "open_code",
        "open_data",
        "open_material",
        "open_analysis"
      ),
      labels = c(
        "Preregistration",
        "Open code",
        "Open data",
        "Open material",
        "Open analysis"
      )
    )
  ) %>%
  mutate(
    study_type = factor(
      study_type,
      levels = c(
        "quantitative",
        "qualitative",
        "mixed",
        "review",
        "conceptional",
        "methodical"
      )
    )
  )

# Plot A: Study types
plot3a <- ggplot(data_3, aes(y = reorder(study_type, -n_total), x = n_total)) +
  geom_col(position = "dodge", alpha = 0.3) +
  geom_text(
    aes(label = paste0(Perc_total, " %")),
    position = position_dodge(width = 0.8),
    hjust = -0.2
  ) +
  theme_bw() +
  scale_x_continuous(
    expand = expansion(mult = c(0, 0.01)),
    limits = c(0, 205)
  ) +
  labs(x = "Article type", y = "N Articles")
plot3a


# Plot B: Methods in the study types
plot3b <- ggplot(
  data_3,
  aes(x = open_category, y = percent, fill = open_category)
) +
  geom_col(position = "dodge", color = "black", alpha = 0.8) +
  facet_wrap(~study_type) +
  theme_bw() +
  scale_fill_carto_d(name = "Open science practice", palette = "Safe") +
  theme(axis.text.x = element_blank(), axis.ticks.x = element_blank()) +
  labs(x = element_blank(), y = "Articles (%)")

plot3b

ggsave("figure_3.pdf", plot3b, width = 20, height = 10, units = "cm")
