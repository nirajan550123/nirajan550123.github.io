-- 05_income_spatial_join.sql
-- Area-weighted aggregation of census tract income to neighborhood planning areas.
-- Run against the `austin_heat` PostGIS database.

-- One-time database setup:
--   CREATE DATABASE austin_heat;
--   \c austin_heat
--   CREATE EXTENSION postgis;

-- Tracts arrive in NAD83 (EPSG:4269); neighborhoods are WGS84 (EPSG:4326).
-- Transform tracts to 4326 so the spatial operations share one coordinate system.
UPDATE income_tracts
SET geometry = ST_Transform(geometry, 4326);

SELECT UpdateGeometrySRID('income_tracts', 'geometry', 4326);

-- Area-weighted median income per neighborhood:
--   weight each intersecting tract by the area of its overlap with the neighborhood.
SELECT
  n.name,
  SUM(t.median_income * ST_Area(ST_Intersection(n.geometry, t.geometry)))
    / NULLIF(SUM(ST_Area(ST_Intersection(n.geometry, t.geometry))), 0)
    AS income_weighted
FROM neighborhoods n
JOIN income_tracts t
  ON ST_Intersects(n.geometry, t.geometry)
WHERE t.median_income IS NOT NULL
GROUP BY n.name
ORDER BY n.name;

-- Exported to neighborhood_income.csv via:
--   \copy (<query above>) TO 'neighborhood_income.csv' WITH CSV HEADER;
