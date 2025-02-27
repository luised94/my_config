# First, load the required package
library(cranlogs)

# Next, get the download logs for the last 12 months
logs <- cran_downloads(start = Sys.Date() - 365, end = Sys.Date())

# Then, group the logs by month and package and count the number of downloads
download_counts <- logs %>%
  group_by(date = floor_date(date, "month"), package) %>%
  summarise(downloads = n())

# Finally, sort the download counts in descending order and print the top 10 packages for each month
download_counts %>%
  arrange(date, desc(downloads)) %>%
  group_by(date) %>%
  top_n(10) %>%
  ungroup() %>%
  select(date, package, downloads) %>%
  print()
