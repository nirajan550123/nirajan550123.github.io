Rooftop Solar Potential Across Data Environments
Estimating building-level rooftop solar potential with one method and two very different elevation data realities: airborne LiDAR (Austin, Texas, USA) and an open global DSM (Kathmandu, Nepal).
---
Why this project exists
Most rooftop-solar GIS demos run a clean pipeline over a US city with high-quality
airborne LiDAR and stop there. That is fine as a tutorial, but it hides the
problem that actually defines this work in most of the world: the ideal data
usually does not exist for your study area.
Nepal is a concrete example. Airborne LiDAR has been flown there, but it sits
behind government and vendor gatekeeping and is not openly downloadable. So a
"LiDAR rooftop solar for Nepal" project cannot be built honestly from open data
today.
This project turns that constraint into the point. It runs the same analytical
method in two settings:
Austin, Texas with real USGS 3DEP airborne LiDAR (1 m), to prove the full
point-cloud-to-energy pipeline.
Kathmandu, Nepal with an open ~30 m global DSM plus OpenStreetMap
footprints, to show what the method can and cannot deliver where LiDAR is
absent.
The deliverable is not "I can process LiDAR." It is "I can produce a usable
energy analysis regardless of whether ideal data exists, and I can state
precisely what is gained and lost when it is not."
---
The method (shared across both cities)
```
elevation surface (DSM)
        │
        ├── slope (Horn 3x3)
        ├── aspect  ──► aspect score (equator-facing = best; both cities N hemisphere)
        │
   building footprints (OSM)
        │
        ▼
 per-building zonal aggregation
        │
        ▼
 usable area × GHI × aspect score × panel efficiency × performance ratio
        │
        ▼
 estimated annual kWh per building
```
`src/solar_suitability.py` holds the shared slope/aspect and per-building logic.
Austin and Kathmandu call the identical functions. Only the input surface and
its resolution differ. That is the methods-transfer hinge.
---
What is honestly different between the two cities
	Austin (LiDAR)	Kathmandu (open DSM)
Surface source	USGS 3DEP airborne LiDAR	Copernicus GLO-30 / AW3D30
Resolution	~1 m	~30 m
Roof planes resolved?	Yes (per-facet slope/aspect)	No (footprint-level screen only)
Footprints	OSM	OSM (urban core)
What the estimate means	Per-roof suitability	Per-building suitability screen
The 30 m limitation is stated, not hidden. At 30 m you cannot recover the
slope and aspect of an individual roof facet, so the Kathmandu output is a
footprint-level screen (which buildings are plausibly worth a closer look),
not a roof-design tool. Writing this down is the most credible part of the project.
A second honesty note: open building-footprint datasets disagree for Kathmandu
(OSM vs Google Open Buildings vs Microsoft differ by roughly 50% in total
building area), and OSM completeness is strong in the urban core but weaker in
peri-urban and informal areas. The project uses OSM over the urban core and
flags this sensitivity rather than pretending the footprints are ground truth.
---
Repository layout
```
rooftop-solar/
├── environment.yml                  # conda env (PDAL, rasterio, geopandas, osmnx, ...)
├── README.md
├── src/
│   ├── point_cloud_to_surfaces.py   # Austin: LAZ -> DSM + DTM (PDAL)
│   ├── terrain_metrics.py           # optional: export slope/aspect rasters for QC
│   ├── solar_suitability.py         # SHARED slope/aspect + per-building estimate
│   └── kathmandu_transfer.py        # Kathmandu: OSM footprints + open DSM -> estimate
├── notebooks/
│   └── 01_run_pipeline.ipynb        # runs both ends, makes figures
├── data/
│   ├── austin/                      # drop your 3DEP tile.laz here
│   └── kathmandu/                   # drop your reprojected dsm.tif here
├── outputs/                         # generated rasters + per-building GeoJSON
└── docs/                            # writeup figures, dashboard notes
```
---
How to run
0. Environment
```bash
conda env create -f environment.yml
conda activate rooftop-solar
```
1. Austin (LiDAR side)
Tile used during development:
`USGS_LPC_TX_Central_B1_2017_stratmap17_50cm_3097424b3_LAS_2019.laz`
(TX Central B1 2017, West Lake Hills / Austin). Place it at `data/austin/tile.laz`.
```bash
# Confirm the tile's CRS first (the script prints a summary), then set --epsg.
python src/point_cloud_to_surfaces.py \
    --laz data/austin/tile.laz \
    --out-dir outputs/austin \
    --resolution 1.0 \
    --epsg 6578            # VERIFY against the printed summary

# optional QC rasters
python src/terrain_metrics.py --dsm outputs/austin/dsm.tif --out-dir outputs/austin
```
Then aggregate to OSM footprints (in a notebook or short script) via
`building_suitability(footprints, "outputs/austin/dsm.tif", "outputs/austin/buildings_solar.geojson", annual_ghi_kwh_m2=1700)`.
2. Kathmandu (transfer side)
Download a Copernicus GLO-30 DSM for a small Kathmandu urban-core box, reproject
to UTM 45N (EPSG:32645), and save as `data/kathmandu/dsm.tif`. Then:
```bash
python src/kathmandu_transfer.py \
    --dsm data/kathmandu/dsm.tif \
    --out outputs/kathmandu/buildings_solar.geojson \
    --bbox 27.69 85.30 27.73 85.34
```
3. Dashboard
Publish `outputs/austin/buildings_solar.geojson` and
`outputs/kathmandu/buildings_solar.geojson` to ArcGIS Online as two web maps,
symbolised by `annual_kwh`, with a side-by-side panel contrasting the two data
environments.
---
Solar modelling note
The Python code computes the geometric suitability (slope, aspect, usable
area) and a transparent first-order energy estimate. For the Austin side, a more
rigorous insolation surface (sky-view, horizon shading, direct/diffuse split)
can be produced in ArcGIS Pro's Area Solar Radiation tool on the 1 m DSM and
swapped in. The split between a reproducible Python core and an optional
higher-fidelity GIS step is intentional and is described in the writeup rather
than hidden.
Replace the placeholder GHI values (Austin ~1700, Kathmandu ~1800 kWh/m²/yr)
with cited figures from the Global Solar Atlas for your exact AOIs before
reporting any numbers.
---
Data sources
USGS 3DEP Lidar Point Cloud (public domain), via 3DEP LidarExplorer.
Copernicus GLO-30 DSM / JAXA AW3D30 (open global elevation).
OpenStreetMap building footprints (© OpenStreetMap contributors, ODbL).
Global Solar Atlas (irradiation values for reporting).
Limitations (read before citing any number)
Kathmandu estimates are a footprint-level screen at 30 m, not roof-facet design.
Energy model is first-order; it does not model inter-building shading in Python
(use ArcGIS Pro Area Solar Radiation for that on the LiDAR side).
OSM footprint completeness and the choice of footprint dataset materially
affect Kathmandu totals.
GHI placeholders must be replaced with cited site values.
License
Code released under the MIT License. Data under their respective licenses above.
---
Repository scripts (quick map)
`src/point_cloud_to_surfaces.py` — Austin: PDAL pipeline, LAZ → DSM/DTM (optional pure-Python path; the GUI ArcGIS Pro path is documented in docs/LiDAR_Processing_Methodology.docx).
`src/solar_suitability.py` — shared slope/aspect + per-building solar estimate (used by both cities).
`src/run_austin.py` — Austin run: fetch OSM footprints, estimate per-building solar from the LiDAR DSM.
`src/run_kathmandu.py` — Kathmandu run: reproject Copernicus GLO-30 DSM, fetch OSM, estimate (footprint-level screen).
`src/comparative_analysis.py` — computes the comparative statistics (writes stats.json).
`src/comparative_plots.py` — generates the distribution and resolution-bias figures.
`src/terrain_metrics.py` — optional slope/aspect raster export for QC.
`notebooks/01_run_pipeline.ipynb` — runs both ends and builds the comparison figure.
Documents
`docs/LiDAR_Processing_Methodology.docx` — full point-cloud-to-surface workflow with screenshots.
`docs/Rooftop_Solar_Comparative_Analysis.docx` — the comparative findings (resolution-bias diagnosis).
Key finding
Running the identical method on 1 m LiDAR (Austin) vs a 30 m open DSM (Kathmandu) shows the coarse DSM
flattens roof slope (40.3° → 3.7°), marks ~all roof area usable (0.47 → 1.00), and drops ~87% of small
buildings (96% → 13% footprint survival). These biases inflate the coarse-data estimates, so open-DSM
rooftop solar should be read as a relative screen, not absolute design figures.
