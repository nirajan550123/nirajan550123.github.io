# Transit Dependency Index (TDI) and Service Gap Analysis Tool
# Developed for GIS II | Spring 2025 | Texas State University

# Description:
# This tool calculates a TDI using selected socio-economic indicators
# and identifies areas that are unserved by public transport (bus stops).

# Import Required Modules

import arcpy
import os
import pandas as pd
import numpy as np
from scipy.stats import zscore
from statsmodels.tools.tools import add_constant
from statsmodels.stats.outliers_influence import variance_inflation_factor

# Initialize Tool
arcpy.AddMessage("Starting Transit Dependency Index (TDI) and Service Gap Analysis Tool...")

# Get parameters from the GUI

input_fc = arcpy.GetParameterAsText(0)                      # Input Polygon feature class (e.g., census tracts)
bus_stops = arcpy.GetParameterAsText(1)                     # Bus stop feature class
distance = arcpy.GetParameterAsText(2)                      # Distance for service area
street_fc = arcpy.GetParameterAsText(3)                     # Street network for unserved clip
network_dataset = arcpy.GetParameterAsText(4)               # Network dataset for service area
selected_fields = arcpy.GetParameterAsText(5).split(";")    # Demographic fields used to calculate TDI
weight_mode = arcpy.GetParameterAsText(6).lower()           # 'equal' or 'custom'
weight_string = arcpy.GetParameterAsText(7)                 # Custom weights
output_tdi = arcpy.GetParameterAsText(8)                    # Final TDI output
output_unserved = arcpy.GetParameterAsText(9)               # Final unserved street output

# Weight Handling for TDI Calculations

arcpy.AddMessage(f"Processing weights with {weight_mode} weight...")

if weight_mode == "equal":
    weights = [1.0 for _ in selected_fields]
elif weight_mode == "custom":
    weights = [float(w.strip()) for w in weight_string.split(";")]
    if len(weights) != len(selected_fields):
        arcpy.AddError("Custom weights do not match selected fields.")
        raise ValueError("Mismatch between weights and selected fields.")
else:
    arcpy.AddError("Weight mode must be 'equal' or 'custom'.")
    raise ValueError("Invalid weight mode.")

# Export attribute table to CSV for processing

arcpy.AddMessage("Preparing input data for processing...")
csv_output = os.path.join(arcpy.env.scratchFolder, "TDI_Export.csv")
arcpy.TableToTable_conversion(input_fc, os.path.dirname(csv_output), os.path.basename(csv_output))
df = pd.read_csv(csv_output)

# Z-score and W-score calculation for each selected field

for field in selected_fields:
    arcpy.AddMessage(f"Processing: {field}")
    z_field = f"Zscore_{field}"
    w_field = f"W_{field}"

    # Calculate z-scores
    raw_z = zscore(df[field].astype(float), nan_policy='omit')
    df[z_field] = raw_z

    # Assign W-score based on z-score thresholds
    df[w_field] = np.select(
        [raw_z < 0, (raw_z >= 0) & (raw_z < 1), raw_z >= 1],
        [0, 0.5, 1],
        default=np.nan
    )

    # Add Z and W fields to the feature class if not already present
    for new_field in [z_field, w_field]:
        if new_field not in [f.name for f in arcpy.ListFields(input_fc)]:
            arcpy.AddField_management(input_fc, new_field, "DOUBLE")

    # Update the feature class with calculated values
    with arcpy.da.UpdateCursor(input_fc, [field, z_field, w_field]) as cursor:
        for row in cursor:
            val = row[0]
            if val is None:
                row[1], row[2] = None, None
            else:
                z_val = (val - df[field].mean()) / df[field].std()
                row[1] = z_val
                if z_val < 0:
                    row[2] = 0
                elif z_val < 1:
                    row[2] = 0.5
                else:
                    row[2] = 1
            cursor.updateRow(row)

# Calculate Transit Dependency Index (TDI)

arcpy.AddMessage("Calculating Transit Dependency Index (TDI)...")
tdi_field = "TDI_Index"
w_fields = [f"W_{f}" for f in selected_fields]

# Add TDI field to the feature class if missing
if tdi_field not in [f.name for f in arcpy.ListFields(input_fc)]:
    arcpy.AddField_management(input_fc, tdi_field, "DOUBLE")

# Calculate weighted average of W-scores
with arcpy.da.UpdateCursor(input_fc, w_fields + [tdi_field]) as cursor:
    for row in cursor:
        values = row[:-1]
        if None in values:
            row[-1] = None
        else:
            weighted_sum = sum(v * weights[i] for i, v in enumerate(values))
            row[-1] = weighted_sum / sum(weights)
        cursor.updateRow(row)

# Multicollinearity check using VIF

arcpy.AddMessage("Checking for multicollinearity (VIF)...")
df_vif = df[selected_fields].dropna()
if df_vif.shape[0] > 0 and df_vif.shape[1] > 1:
    X = add_constant(df_vif)
    vif_data = pd.DataFrame()
    vif_data["Variable"] = X.columns
    vif_data["VIF"] = [variance_inflation_factor(X.values, i) for i in range(X.shape[1])]
    vif_data.to_csv(os.path.join(arcpy.env.scratchFolder, "VIF_Results.csv"), index=False)
    for _, row in vif_data.iterrows():
        arcpy.AddMessage(f" - {row['Variable']}: {row['VIF']:.2f}")
else:
    arcpy.AddWarning("VIF check skipped due to insufficient valid data.")

# Generate service area from bus stops using network dataset

arcpy.AddMessage("Generating service area from bus stops...")
service_area_layer = "ServiceAreaLayer"
arcpy.na.MakeServiceAreaLayer(
    in_network_dataset=network_dataset,
    out_network_analysis_layer=service_area_layer,
    impedance_attribute="Length",
    travel_from_to="TRAVEL_FROM",
    default_break_values=str(distance),
    polygon_type="DETAILED_POLYS",
    merge="NO_MERGE"
)

# Add bus stop locations to the service area layer
sublayers = arcpy.na.GetNAClassNames(service_area_layer)
arcpy.na.AddLocations(service_area_layer, sublayers["Facilities"], bus_stops)
arcpy.na.Solve(service_area_layer)

# Save service area polygons to temp location
service_area_temp = os.path.join(arcpy.env.scratchGDB, "TempServiceArea")
arcpy.CopyFeatures_management(os.path.join(service_area_layer, "Polygons"), service_area_temp)

# Identify Transit-Dependent & Unserved Areas (TDI >= 0.5)

arcpy.AddMessage("Identifying unserved transit-dependent areas...")
transit_areas = os.path.join(arcpy.env.scratchGDB, "TransitDependent")
arcpy.MakeFeatureLayer_management(input_fc, "tdi_layer")
arcpy.SelectLayerByAttribute_management("tdi_layer", "NEW_SELECTION", f'"{tdi_field}" >= 0.5')
arcpy.CopyFeatures_management("tdi_layer", transit_areas)

# Find areas not covered by service area (Symmetric Difference)
unserved_area = os.path.join(arcpy.env.scratchGDB, "Unserved_TDI_Area")
arcpy.SymDiff_analysis(transit_areas, service_area_temp, unserved_area)

# Clip unserved areas to transit-dependent polygons only
clipped_unserved = os.path.join(arcpy.env.scratchGDB, "Clipped_Unserved_TDI")
arcpy.Clip_analysis(unserved_area, transit_areas, clipped_unserved)

# Save Final Outputs
arcpy.AddMessage("Saving outputs...")
arcpy.CopyFeatures_management(clipped_unserved, output_tdi)

# Clean output by keeping only relevant fields
keep_fields = [f.name for f in arcpy.ListFields(input_fc)
               if not f.required and (
                   f.name in selected_fields or
                   f.name == tdi_field or
                   f.name.startswith("Zscore_") or
                   f.name.startswith("W_")
               )]
all_fields = [f.name for f in arcpy.ListFields(output_tdi) if not f.required]
fields_to_delete = [f for f in all_fields if f not in keep_fields]
if fields_to_delete:
    arcpy.DeleteField_management(output_tdi, fields_to_delete)

# Set the output parameter in toolbox
arcpy.SetParameterAsText(8, output_tdi)

# Output unserved streets (clip street network to unserved zones)

arcpy.Clip_analysis(street_fc, clipped_unserved, output_unserved)
arcpy.SetParameterAsText(9, output_unserved)

# Cleanup temporary layers to avoid clutter

arcpy.AddMessage("Cleaning up temporary layers...")
try:
    arcpy.Delete_management(service_area_layer)
    arcpy.Delete_management(service_area_temp)
    arcpy.Delete_management("tdi_layer")
    arcpy.Delete_management(transit_areas)
    arcpy.Delete_management(unserved_area)
    arcpy.Delete_management(clipped_unserved)
except:
    arcpy.AddWarning("Some temporary layers could not be deleted.")

arcpy.AddMessage("Analysis completed successfully.")