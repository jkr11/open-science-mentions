library(tidyverse)
library(openalexR)

df = read.csv("education_journals.csv", sep=",")
print(df)

journals_data <- oa_fetch(
  entity = "sources",
  identifier = df$Journal.ID
)
