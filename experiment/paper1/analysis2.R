library(readr)
library(dplyr)
library(brms)
library(ggplot2)
library(stringr)
library(scales)

raw <- read_csv(
  "experiment/paper1/all_papers_data_with_second_trial.csv",
  na = c("", "NA", "None")
)


combined_df <- raw %>%
  mutate(has_any_link = as.logical(second_trial_any_link)) %>%
  filter(!is.na(publication_year)) %>%
  filter(publication_year != 2026) %>%
  filter(publication_year > 2019) %>%
  filter(journal_short != "flr") %>%
  group_by(journal_long, publication_year) %>%
  summarise(
    total_papers = n_distinct(openalex_id),
    unique_linked_papers = sum(has_any_link, na.rm = TRUE),
    proportion_linked = unique_linked_papers / total_papers,
    .groups = "drop"
  ) %>%
  group_by(journal_long) %>%
  mutate(
    FigureName = str_glue("{journal_long} (N = {sum(total_papers)})")
  ) %>%
  ungroup() %>%
  mutate(publication_year_centered = publication_year - 2019)

papers_per_year <- combined_df %>%
  group_by(publication_year) %>%
  summarise(total_unique_linked = sum(unique_linked_papers, na.rm = TRUE)) %>%
  arrange(publication_year)

ggplot(
  papers_per_year,
  aes(x = publication_year, y = total_unique_linked)
) +
  geom_line() +
  geom_point() +
  scale_x_continuous(breaks = papers_per_year$publication_year) +
  labs(
    title = "Unique Papers With Links Per Year",
    x = "Publication Year",
    y = "Number of Unique Linked Papers"
  ) +
  theme_minimal()


ggplot(
  combined_df,
  aes(x = publication_year, y = proportion_linked, group = journal_long)
) +
  geom_line(aes(color = journal_long), alpha = 0.6, size = 0.7) +
  stat_summary(
    aes(group = 1),
    fun = mean,
    geom = "line",
    color = "black",
    size = 1.2
  ) +
  scale_x_continuous(breaks = unique(combined_df$publication_year)) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(
    title = "Proportion of Linked Papers Per Year by Journal (with mean)",
    x = "Publication Year",
    y = "Proportion Linked",
    color = "Journal"
  ) +
  theme_minimal() +
  theme(legend.position = "right")


model <- brm(
  unique_linked_papers | trials(total_papers) ~ publication_year_centered +
    (1 | journal_long),
  data = combined_df,
  family = binomial()
)

#unique_linked_papers | trials(total_papers) ~
#  publication_year_centered +
#  (publication_year_centered | journal_long)

summary(model)
plot(model)
pp_check(model)
post <- posterior_samples(model)
ggplot(post, aes(x = b_publication_year_centered)) +
  geom_density() +
  labs(title = "Posterior for Year Effect (Centered)")

model <- brm(
  unique_linked_papers | trials(total_papers) ~ publication_year_centered +
    (1 | journal_long),
  data = combined_df,
  family = binomial()
)

#unique_linked_papers | trials(total_papers) ~
#  publication_year_centered +
#  (publication_year_centered | journal_long)

summary(model)
plot(model)
pp_check(model)
post <- posterior_samples(model)
ggplot(post, aes(x = b_publication_year_centered)) +
  geom_density() +
  labs(title = "Posterior for Year Effect (Centered)")


model <- brm(
  unique_linked_papers | trials(total_papers) ~ publication_year_centered +
    (publication_year_centered | journal_long),
  data = combined_df,
  family = binomial()
)
#unique_linked_papers | trials(total_papers) ~
#  publication_year_centered +
#  (publication_year_centered | journal_long)

summary(model)
plot(model)
pp_check(model)
post <- posterior_samples(model)
ggplot(post, aes(x = b_publication_year_centered)) +
  geom_density() +
  labs(title = "Posterior for Year Effect (Centered)")


library(dplyr)
library(purrr)
library(brms)

journals <- unique(combined_df$journal_long)

results <- purrr::map_dfr(journals, function(j) {
  df_sub <- combined_df %>%
    filter(journal_long != j)

  fit <- brm(
    unique_linked_papers | trials(total_papers) ~ publication_year_centered +
      (publication_year_centered | journal_long),
    data = df_sub,
    family = binomial(),
    chains = 4,
    iter = 2000,
    warmup = 1000,
    refresh = 0
  )

  fx <- fixef(fit)

  tibble(
    left_out = j,
    beta_year = fx["publication_year_centered", "Estimate"],
    ci_low = fx["publication_year_centered", "Q2.5"],
    ci_high = fx["publication_year_centered", "Q97.5"]
  )
})

ggplot(results, aes(x = reorder(left_out, beta_year), y = beta_year)) +
  geom_point() +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_high)) +
  coord_flip()
