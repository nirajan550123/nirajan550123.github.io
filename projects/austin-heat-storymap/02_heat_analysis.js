// =====================================================================
// 02_heat_analysis.js
// Austin urban heat: summer land surface temperature vs tree canopy and
// impervious surface, across all 65 Neighborhood Planning Areas.
//
// WHAT THIS SCRIPT PRODUCES
//   1. Per-neighborhood mean + std-dev summer LST (degrees C)
//   2. Per-neighborhood mean tree-canopy % and impervious-surface %
//   3. City-wide correlations (LST vs canopy, LST vs impervious) across
//      all 65 neighborhoods  <-- your headline, selection-bias-free metric
//   4. An exported table (CSV) you can join back to your story-map data
//
// DATA PROVENANCE (put this in your README)
//   Boundaries : asset built in 01_create_boundary_asset.js from City of
//                Austin NPA layer (inrm-c3ee), dissolved by name -> 65 areas
//   LST        : Landsat 8 & 9 Collection 2 Level-2 thermal band (ST_B10),
//                clear-sky scenes, June-August 2022-2024, median composite,
//                scaled to degrees Celsius
//   Canopy     : NLCD Tree Canopy Cover (see TCC_YEAR below)
//   Impervious : NLCD Impervious Surface (see NLCD_YEAR below)
//
// DEFENSIBILITY NOTE
//   The mean is the headline per-neighborhood value. The std-dev describes
//   how much surface temperature VARIES WITHIN each neighborhood (i.e. how
//   much the single mean is smoothing over). It is NOT an error bar and not
//   a basis for significance testing.
// =====================================================================

// ----- inputs -----
var npa = ee.FeatureCollection('projects/thesis-lulc-496818/assets/austin_npa');
var YEARS   = [2022, 2023, 2024];     // summers to composite for LST
var MONTHS  = [6, 7, 8];              // June, July, August
var CLOUD_MAX = 20;                   // % cloud cover ceiling per scene

// =====================================================================
// STEP 1.  Summer LST composite from Landsat 8 + 9 (Collection 2, L2)
// =====================================================================
// Collection 2 Level-2 surface-temperature band ST_B10 is in Kelvin*0.00341802
// + 149.0. We convert to Celsius. We mask clouds using the QA_PIXEL band.

function maskAndScaleLST(img) {
  // Bit 3 of QA_PIXEL = cloud, bit 4 = cloud shadow
  var qa = img.select('QA_PIXEL');
  var cloud = qa.bitwiseAnd(1 << 3).neq(0);
  var shadow = qa.bitwiseAnd(1 << 4).neq(0);
  var clear = cloud.or(shadow).not();
  // ST_B10 -> Celsius
  var lstC = img.select('ST_B10').multiply(0.00341802).add(149.0).subtract(273.15);
  return lstC.updateMask(clear).rename('lst_c')
             .copyProperties(img, ['system:time_start']);
}

// pull both Landsat 8 and 9, filter to Austin, summers, low cloud
var l8 = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2');
var l9 = ee.ImageCollection('LANDSAT/LC09/C02/T1_L2');
var landsat = l8.merge(l9)
  .filterBounds(npa)
  .filter(ee.Filter.calendarRange(YEARS[0], YEARS[YEARS.length - 1], 'year'))
  .filter(ee.Filter.calendarRange(MONTHS[0], MONTHS[MONTHS.length - 1], 'month'))
  .filter(ee.Filter.lt('CLOUD_COVER', CLOUD_MAX))
  .map(maskAndScaleLST);

print('Landsat scenes used for LST composite:', landsat.size());

// median composite = the "typical summer surface temperature" surface
var lst = landsat.select('lst_c').median().rename('lst_c');

// =====================================================================
// STEP 2.  NLCD tree canopy and impervious surface
// =====================================================================
// Tree canopy: USFS/NLCD TCC. Impervious: NLCD impervious layer.
// We grab the most recent available and record the year for the README.

// NLCD impervious (NLCD 2021 release is widely available in GEE)
var NLCD_YEAR = 2021;
var nlcd = ee.ImageCollection('USGS/NLCD_RELEASES/2021_REL/NLCD')
  .filter(ee.Filter.eq('system:index', String(NLCD_YEAR)))
  .first();
var impervious = nlcd.select('impervious').rename('impervious_pct');

// Tree canopy cover: USFS TCC suite, 2023 release (annual data through 2023).
// We average canopy across the years of our window that exist in the product
// (2022-2023) for consistency with the LST composite. Canopy changes slowly,
// so this matches the LST treatment without materially changing the values.
var TCC_YEARS = [2022, 2023];
var canopy = ee.ImageCollection('USGS/NLCD_RELEASES/2023_REL/TCC/v2023-5')
  .filter(ee.Filter.calendarRange(TCC_YEARS[0], TCC_YEARS[TCC_YEARS.length - 1], 'year'))
  .filter(ee.Filter.eq('study_area', 'CONUS'))
  .select('Science_Percent_Tree_Canopy_Cover')
  .mean()                       // multi-year mean canopy
  .rename('canopy_pct');

// =====================================================================
// STEP 3.  Zonal statistics per neighborhood
// =====================================================================
// LST: mean AND std-dev (std-dev = within-neighborhood spread, not error).
// Canopy / impervious: mean only.

var lstStats = lst.reduceRegions({
  collection: npa,
  reducer: ee.Reducer.mean().combine({reducer2: ee.Reducer.stdDev(), sharedInputs: true}),
  scale: 30
});
// reduceRegions names outputs 'mean' and 'stdDev' -> rename for clarity
lstStats = lstStats.map(function (f) {
  return f.set({ lst_c: f.get('mean'), lst_sd: f.get('stdDev') });
});

var canopyStats = canopy.reduceRegions({collection: lstStats, reducer: ee.Reducer.mean(), scale: 30})
  .map(function (f) { return f.set('canopy_pct', f.get('mean')); });

var allStats = impervious.reduceRegions({collection: canopyStats, reducer: ee.Reducer.mean(), scale: 30})
  .map(function (f) {
    return ee.Feature(f.geometry(), {
      name:           f.get('name'),
      lst_c:          f.get('lst_c'),
      lst_sd:         f.get('lst_sd'),
      canopy_pct:     f.get('canopy_pct'),
      impervious_pct: f.get('mean')   // impervious reducer's mean output
    });
  });

print('Per-neighborhood stats (first 5):', allStats.limit(5));

// =====================================================================
// STEP 4.  City-wide correlations across all 65 neighborhoods
//          (this is your defensible, selection-bias-free headline)
// =====================================================================
function pearson(fc, xField, yField) {
  var arr = fc.filter(ee.Filter.notNull([xField, yField]))
              .reduceColumns(ee.Reducer.pearsonsCorrelation(), [xField, yField]);
  return arr.get('correlation');
}

print('--- CITY-WIDE CORRELATIONS (n = 65 neighborhoods) ---');
print('LST vs tree canopy (expect strong negative):',
      pearson(allStats, 'canopy_pct', 'lst_c'));
print('LST vs impervious surface (expect positive):',
      pearson(allStats, 'impervious_pct', 'lst_c'));

// =====================================================================
// STEP 5.  Quick visual check on the map
// =====================================================================
Map.centerObject(npa, 11);
Map.addLayer(lst.clip(npa), {min: 28, max: 42,
  palette: ['2c7fb8','7fcdbb','ffffbf','fd8d3c','bd0026']}, 'Summer LST (C)');

// =====================================================================
// STEP 6.  Export the full 65-neighborhood table as CSV
//          After running: Tasks tab -> RUN 'austin_heat_stats'
// =====================================================================
Export.table.toDrive({
  collection: allStats,
  description: 'austin_heat_stats',
  fileFormat: 'CSV',
  selectors: ['name', 'lst_c', 'lst_sd', 'canopy_pct', 'impervious_pct']
});
