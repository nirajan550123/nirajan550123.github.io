# The Heat Beneath the City — Austin Urban Heat Island Story Map

An **interactive scrollytelling web map** of urban heat in Austin, Texas. As the
reader scrolls, a sticky Leaflet map flies between neighborhoods and recolors to
tell a five-part story: where the city is hottest, how tree canopy cools it, how
impervious surfaces heat it, and how that burden lines up with income.

**Live demo:** https://nirajan550123.github.io/projects/austin-heat-storymap/

![Story map preview](preview.jpg)

## What it does
- A **sticky full-screen map** stays in view while narrative "steps" scroll past.
- Each step **flies the map** to a new extent and **recolors the neighborhoods**
  by a different variable (surface temperature → tree canopy → impervious surface
  → median income).
- Every neighborhood is **clickable** at any time, with a popup showing its
  surface temperature, canopy %, impervious %, and median income.
- A live **legend** updates with each variable, and key **statistics**
  (hottest neighborhood, canopy–heat correlation) are computed from the data
  in-browser.

## Built with
Vanilla **JavaScript** + **Leaflet** (no framework), **GeoJSON**, CARTO basemap
tiles, and the IntersectionObserver API for scroll-driven transitions. The whole
experience is one self-contained HTML file plus a GeoJSON data file.

## The story
1. **The city** — Austin's neighborhoods, colored by summer land surface temperature.
2. **The hotspots** — the urban core and east side run hottest.
3. **The shade** — tree canopy cover; the coolest areas are the leafiest.
4. **The pavement** — impervious surface; the hottest areas are the most paved.
5. **Who feels it** — median income; heat exposure tracks with lower-income areas.

## ⚠️ Data note (read this)
The version in this repo ships with **realistic, representative placeholder data**
for 16 Austin neighborhoods so the experience is fully functional. The spatial
patterns (hotter east/core, cooler leafy west, canopy–heat inverse relationship)
reflect documented urban-heat findings, but the exact per-neighborhood numbers are
modeled, not measured. **Swapping in real published data is a documented, one-file
change** — see below.

## Replacing with real Austin data
The map reads a single GeoJSON file (`austin_heat.geojson`). To make it fully
authoritative, replace that file with real data carrying the same property names.

**1. Neighborhood boundaries** — City of Austin open data:
   https://data.austintexas.gov → "Boundaries: City of Austin Neighborhoods"
   (export as GeoJSON).

**2. Land surface temperature** — derive from a summer **Landsat 8/9** thermal
   band (Band 10) scene over Austin in Google Earth Engine or ArcGIS Pro, convert
   to °C, and compute the **zonal mean per neighborhood** (Zonal Statistics).
   This is the same LST workflow from my NDVI–LST project.

**3. Tree canopy & impervious surface** — **NLCD** (mrlc.gov) tree-canopy and
   impervious layers; zonal mean per neighborhood.

**4. Median household income** — U.S. Census **ACS** table B19013 at the tract
   level, area-weighted to neighborhoods (or use Census place/tract GeoJSON directly).

**5. Join** all four into the neighborhood GeoJSON so each feature's `properties`
   has exactly these keys:

```json
{
  "name": "East Austin",
  "lst_c": 38.4, "lst_f": 101.1,
  "canopy_pct": 11.0,
  "impervious_pct": 73.0,
  "median_income_k": 44
}
```

Save it as `austin_heat.geojson`, commit, and the map updates automatically — no
other code changes needed.

## Skills demonstrated
Interactive **web mapping (Leaflet, JavaScript)** · **scrollytelling / data
storytelling** · GeoJSON authoring · zonal statistics &
multi-source spatial joins · remote sensing (Landsat LST, NLCD) · framing a
spatial-equity narrative for a general audience.

## Author
**Nirajan Tripathi** — M.S. Geography, Texas State University
[Portfolio](https://nirajan550123.github.io/) ·
[LinkedIn](https://www.linkedin.com/in/nirajan-tripathi-5434a8308/) ·
[GitHub](https://github.com/nirajan550123)
