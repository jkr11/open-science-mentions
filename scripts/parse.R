library(openalexR)
library(dplyr)

top_journals_sped <- list(
  "International Journal of Inclusive Education" = c(70, 99),
  "European Journal of Special Needs Education" = c(50, 77),
  "Journal of Learning Disabilities" = c(39, 54),
  "International Journal of Disability, Development and Education" = c(38, 57),
  "Remedial and Special Education" = c(38, 57),
  "Exceptional Children" = c(32, 52),
  "Journal for the Education of Gifted Young Scientists" = c(31, 45),
  "Journal of Positive Behavior Interventions" = c(31, 41),
  "Journal of Special Education Technology" = c(29, 53),
  "Preventing School Failure: Alternative Education for Children and Youth" = c(29, 43),
  "TEACHING Exceptional Children" = c(29, 40),
  "Journal of Behavioral Education" = c(29, 39),
  "Gifted Child Quarterly" = c(28, 63),
  "The Journal of Special Education" = c(28, 45),
  "Journal of Intellectual Disabilities" = c(28, 43),
  "Learning Disability Quarterly" = c(28, 43),
  "Journal of Emotional and Behavioral Disorders" = c(28, 36),
  "Research and Practice for Persons with Severe Disabilities" = c(27, 45),
  "Intervention in School and Clinic" = c(27, 34),
  "Career Development and Transition for Exceptional Individuals" = c(26, 43)
)

top_journals_ed <- list(
  "",
)

journal_names <- c("International Journal of Inclusive Education")
filter_str <- paste0("source.display_name:", shQuote(journal_names), collapse = ",")
works <- oa_fetch(
  entity = "works",
  filter = filter_str,
  per_page = 200,
  verbose = TRUE,
  paging = "cursor"
)
