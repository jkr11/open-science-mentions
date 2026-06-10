library(dplyr)
library(readr)
library(tidyr)

all <- read_csv(
  "experiment/paper1/all_papers_data.csv",
  na = c("", "NA", "None")
)
checked <- read_csv(
  "experiment/paper1/checked_links_dedup.csv",
  na = c("", "NA", "None")
)

joined <- all %>%
  left_join(
    checked %>%
      select(openalex_id, second_trial_osf, second_trial_git),
    by = "openalex_id"
  ) %>%
  mutate(
    second_trial_osf = replace_na(second_trial_osf, FALSE),
    second_trial_git = replace_na(second_trial_git, FALSE),
    second_trial_any_link = second_trial_osf | second_trial_git
  )

write_csv(joined, "experiment/paper1/all_papers_data_with_second_trial.csv")
