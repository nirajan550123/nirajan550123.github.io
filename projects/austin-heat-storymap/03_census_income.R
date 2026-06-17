# 03_census_income.R
# Retrieve median household income for Travis County census tracts and load
# into PostGIS for the tract-to-neighborhood spatial join.
#
# Variable: ACS 2018-2022 5-year estimates, table B19013 (median household income)
# Output:   table `income_tracts` in the `austin_heat` PostGIS database

library(tidycensus)
library(sf)
library(DBI)
library(RPostgres)

# Census API key (register free at https://api.census.gov/data/key_signup.html)
census_api_key("YOUR_CENSUS_API_KEY", install = TRUE, overwrite = TRUE)
readRenviron("~/.Renviron")

# Pull tract-level median household income with geometry
travis_income <- get_acs(
  geography = "tract",
  variables = "B19013_001",   # median household income
  state     = "TX",
  county    = "Travis",
  year      = 2022,           # ACS 2018-2022 5-year
  geometry  = TRUE
)
travis_income$median_income <- travis_income$estimate

# Connect to the PostGIS database and write the tracts table
con <- dbConnect(RPostgres::Postgres(),
                 host = "localhost", port = 5432,
                 dbname = "austin_heat",
                 user = "postgres", password = Sys.getenv("PGPASSWORD"))

st_write(travis_income, con, layer = "income_tracts", delete_layer = TRUE)
dbDisconnect(con)
