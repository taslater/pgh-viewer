-- Join data from assessments to parcels geometry
SELECT
	parcels.gid AS id,
	assessments.yearblt AS yearblt,
	parcels.geom AS geom
FROM assessments
INNER JOIN parcels ON assessments.parid=parcels.pin;


-- Get bounding box from geometry
SELECT ST_Extent(geom) as bextent FROM parcels;
-- returns
-- "BOX(1240746.6087432504 321259.51609410346,1430019.6022744626 497888.99909454584)"


-- Common table expression (CTE) example to expand bounding box
-- Extracts x-min, x-max, y-min, y-max from Postgis box2d data type
WITH bounding_box AS (
	SELECT ST_Extent(geom) as bextent FROM parcels
)
SELECT
	ST_XMin(bextent),
	ST_XMax(bextent),
	ST_YMin(bextent),
	ST_YMax(bextent)
FROM bounding_box;
-- returns
-- 1240746.6087432504	1430019.6022744626	321259.51609410346	497888.99909454584


-- Get geometry touching or withing a bounding box
SELECT geom FROM parcels
WHERE ST_Intersects(
--                xmin     ymin    xmax     ymax    SRID
	ST_MakeEnvelope(1300000, 400000, 1310000, 401000, 2272),
	geom
);

-- Nasty nested centroids query
WITH geomtable AS
(WITH centroids AS
(SELECT
	ST_Centroid(footprints.geom) AS ft_centroid,
 	footprints.gid AS gid,
 	footprints.geom AS ft_geom
FROM footprints
LIMIT 10)
SELECT
	parcels.pin AS parid, centroids.ft_geom, centroids.gid
FROM centroids
INNER JOIN parcels ON ST_Contains(parcels.geom, centroids.ft_centroid))
SELECT
	geomtable.parid,
	geomtable.gid,
	assessments.*,
	geomtable.ft_geom
FROM geomtable
INNER JOIN assessments ON assessments.parid = geomtable.parid

-- Add centroids column to footprints with spatial index
BEGIN;

ALTER TABLE footprints ADD COLUMN centroid geometry(Geometry,2272);

UPDATE footprints SET centroid = ST_Centroid(footprints.geom);

CREATE INDEX centroid_geom_idx ON footprints USING GIST(centroid);

COMMIT;

-- Associate each footprint with intersecting parcels
SELECT
	footprints.gid AS foot_gid,
	COUNT (parcels.gid) AS parcels_count,
	ARRAY_AGG (parcels.gid) AS parcel_gids
FROM footprints
JOIN parcels
ON ST_Intersects(footprints.geom, parcels.geom)
GROUP BY foot_gid
ORDER BY foot_gid;

-- Get table of footprint-parcel intersections with area ratios and abs area
SELECT
	footprints.gid AS foot_gid,
	parcels.gid AS parcel_gid,
	ST_Area(ST_Intersection(footprints.geom, parcels.geom)) / ST_Area(footprints.geom) AS foot_pct,
	ST_Area(ST_Intersection(footprints.geom, parcels.geom)) / ST_Area(parcels.geom) AS parcel_pct,
	ST_Area(ST_Intersection(footprints.geom, parcels.geom)) AS inter_area,
	ST_Intersection(footprints.geom, parcels.geom) AS inter_geom
FROM footprints
JOIN parcels
ON ST_Intersects(footprints.geom, parcels.geom);
-- TO DO: ANALYZE EFFICIENCY USING EXPLAIN ANALYZE


-- Get parcels with duplicate geometries
SELECT
	array_agg(gid) AS dup_geom_gids
FROM parcels
GROUP BY geom
HAVING COUNT(geom) > 1;

-- New table grouping duplicate parcel geometries
BEGIN;

SELECT
	array_agg(pin) AS pins,
	geom
INTO parcels_reduced
FROM parcels
GROUP BY geom;

ALTER TABLE parcels_reduced ADD COLUMN gid SERIAL PRIMARY KEY;

COMMIT;