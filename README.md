# pgh-viewer

Visualizing Pittsburgh

<img width="972" alt="IMG_0877" src="https://user-images.githubusercontent.com/8193781/155641891-51366251-214b-4c7e-b2cb-ad819a2fc1fc.png">
Vizualizing parcel age. Blue is old, red is new.

## Data Sources

### Allegheny County

- [Building footprints](https://www.pasda.psu.edu/uci/DataSummary.aspx?dataset=1195) (spatial vector)
- [Parcels](https://www.pasda.psu.edu/uci/DataSummary.aspx?dataset=1214) (spatial vector)
- [Property assessments](https://data.wprdc.org/dataset/property-assessments) (csv only)

## Setup

### Server

The server provides mbtiles layers using [mbtileserver](https://github.com/consbio/mbtileserver) for fast user visualization.

Spatial analysis is performed using [PostGIS](https://postgis.net).

### Vector tilesets

[MBTiles](https://docs.mapbox.com/help/glossary/mbtiles/) are generated using [Tippecanoe](https://github.com/mapbox/tippecanoe).

### Spatial analysis

[ogr2ogr](https://gdal.org/programs/ogr2ogr.html) is used to load the shapefiles into PostGIS. Shapefiles may contain invalid geometry which can be repaired using [QGIS](https://qgis.org) before loading with `ogr2ogr`.

#### Spatial join

`assessments.csv` contains interesting parcel features, but we would prefer to visualize the building footprints. To associate the interesting data with each footprint, the footprints must be spatially joined with the parcel shapes.

Many footprints (how many?) are contained neatly inside parcels, but some overlap several parcels. These overlaps may be meaningful or accidental. Analysis is required to distinguish meaningful overlaps from accidental.
