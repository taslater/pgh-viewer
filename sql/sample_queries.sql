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