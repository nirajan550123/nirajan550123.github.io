# 04_neighborhoods_to_postgis.R
# Load Austin neighborhood planning areas into PostGIS, dissolved by name to
# 65 unique areas, for the income spatial join.

library(sf)
library(dplyr)
library(DBI)
library(RPostgres)

sf_use_s2(FALSE)  # planar geometry; tolerant of source topology quirks

npa <- st_read("austin_npa.geojson")
npa <- st_make_valid(npa)  # repair self-intersecting edge in source

npa_dissolved <- npa %>%
  group_by(planning_area_name) %>%
  summarise(.groups = "drop") %>%
  rename(name = planning_area_name)

con <- dbConnect(RPostgres::Postgres(),
                 host = "localhost", port = 5432,
                 dbname = "austin_heat",
                 user = "postgres", password = Sys.getenv("PGPASSWORD"))

st_write(npa_dissolved, con, layer = "neighborhoods", delete_layer = TRUE)
dbDisconnect(con)
