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

ALTER TABLE footprints ADD COLUMN centroids geometry(Geometry,2272);

UPDATE footprints SET centroids = ST_Centroid(footprints.geom);

CREATE INDEX centroids_geom_idx ON footprints USING GIST(centroids);

COMMIT;