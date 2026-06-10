library(readr)
library(RSQLite)
library(dplyr)
library(tidyverse)
library(stringr)
library(tidyr)
library(metacheck)

setwd('/home/jkr/work/open-science/open-science/')

data <- read.csv("experiment/paper1/all_papers_data_with_second_trial.csv") |>
  filter(!is.na(publication_year)) |>
  filter(publication_year != 2026) |>
  filter(publication_year > 2019)

count_path <- "experiment/fetch_data/education_journals_count.csv"
count_data <- read.csv(count_path)

summary(count_data$oa_count_recent)

write.csv(data, "final_collected_data.csv")

data_wo_sage <- data |> filter(journal_short != "sage")
data_w_sage <- data |> filter(journal_short == "sage")


summary(data_wo_sage)

summary(data_w_sage)

count(data_wo_sage, journal_short)
count(data_wo_sage, openalex_id)
count(data, publication_year)

conn <- dbConnect(
  RSQLite::SQLite(),
  "/home/jkr/work/open-science/open-science/test_db/index.db"
)
works <- dbGetQuery(conn, "SELECT * FROM works")
summary(works)
