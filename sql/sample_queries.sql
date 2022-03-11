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

-- -- OLD WAY
-- ALTER TABLE parcels_reduced ADD COLUMN gid SERIAL PRIMARY KEY;
-- NEW WAY (apparently better https://wiki.postgresql.org/wiki/Don%27t_Do_This#Don.27t_use_serial)
ALTER TABLE parcels_reduced
ADD COLUMN gid integer primary key generated always as identity;

COMMIT;

-- Silly nested option to create intersections table
BEGIN;

WITH subtable_2 AS (
	WITH subtable_1 AS (
		SELECT
			footprints.gid AS foot_gid,
			parcels_reduced.pins AS pins,
			footprints.geom AS foot_geom,
			parcels_reduced.geom AS parcel_geom
		FROM footprints
		JOIN parcels_reduced
		ON ST_Intersects(footprints.geom, parcels_reduced.geom))
	SELECT
		foot_gid,
		pins,
		ST_Intersection(foot_geom, parcel_geom) AS geom,
		foot_geom,
		parcel_geom
	FROM subtable_1)
SELECT 
	foot_gid,
	pins,
	ST_Area(geom) AS area,
	ST_Area(foot_geom) AS foot_area,
	ST_Area(parcel_geom) AS parcel_area,
	geom
INTO intersections_reduced
FROM subtable_2;

ALTER TABLE intersections_reduced ADD COLUMN gid SERIAL PRIMARY KEY;

CREATE INDEX geom_idx ON intersections_reduced USING GIST(geom);

COMMIT;

-- A monstrosity to find monstrosities
-- Gets the top ten messiest building/parcel intersections

-- Gets the group of parcels that intersect each footprint
WITH grouped_parcels AS (
	SELECT
		foot_gid,
		ST_Collect(array_agg(parcels.geom)) AS geoms
	FROM intersections
	JOIN parcels
	ON parcels.gid = intersections.parcel_gid
	GROUP BY foot_gid
),
-- Get the top ten messiest footprint intersections based on:
-- 1. intersects multiple parcels
-- 2. largest intersection area that is:
--    a) less than 10% of its parcel area
--    a) less than 10% of its footprint area
-- 
-- In other words, find the biggest intersections that are
-- just a small piece of the parent footprint and parent parcel
-- and return that footprint and the parcels that divide it.
weird_intersections AS (
	-- Gets footprints that intersect more than one parcel
	WITH divided_foots AS (
		SELECT foot_gid
		FROM intersections_reduced
		GROUP BY foot_gid
		HAVING COUNT(*) > 1
	)
	SELECT intersections_reduced.foot_gid
	FROM intersections_reduced
	INNER JOIN divided_foots
	ON divided_foots.foot_gid = intersections_reduced.gid
	WHERE area/foot_area < 0.1
	AND area/parcel_area < 0.1
	ORDER BY area DESC
	LIMIT 10)
SELECT
	footprints.geom AS foot_geom,
	grouped_parcels.geoms AS parcels_geoms
FROM weird_intersections
JOIN footprints
ON weird_intersections.foot_gid = footprints.gid
JOIN grouped_parcels
ON grouped_parcels.foot_gid = footprints.gid;

-- finally fast intersections
SET max_parallel_workers = 8;
SET max_parallel_workers_per_gather = 4;

SELECT
	a.gid AS a_gid,
	b.gid AS b_gid,
	ST_Intersection(a.geom, b.geom)
INTO parcel_intersections
FROM parcels_reduced a
JOIN parcels_reduced b
ON ST_Intersects(a.geom, b.geom)
WHERE a.gid < b.gid
AND (
	ST_Overlaps(a.geom, b.geom)
	OR ST_Contains(a.geom, b.geom)
	OR ST_Contains(b.geom, a.geom)
)
AND ST_Area(ST_Intersection(a.geom, b.geom)) > 50;


-- SPLITTING LINE SEGMENTS
SELECT
	a.gid,
	ST_Split(
		a.geom,
		ST_CollectionExtract(
			ST_Collect(array_agg(b.geom))
		)
	) AS split_geom
INTO split_segments
FROM parcels_exploded_nodups a
JOIN parcels_exploded_nodups b
ON ST_Crosses(a.geom, b.geom)
GROUP BY a.gid;

-- Segments to polygons, magic
SELECT (ST_Dump(ST_Polygonize(ST_Node(geom)))).geom
INTO parcels_polygonized
FROM split_segments_all;


-- Merges small area polygons with large neighbors
WITH ungrouped AS (
	SELECT
		a.gid AS small_gid,
		b.gid AS large_gid,
		ST_Length(ST_Intersection(a.geom, b.geom)) AS touch_length,
		ST_Area(b.geom) AS large_area
	FROM flat_parcels a
	JOIN flat_parcels b
	ON ST_Touches(a.geom, b.geom)
	-- small polygon area limit
	WHERE (ST_Area(a.geom) < 100)
	-- neighbors the touch along length > 0 (not point touching)
	AND (ST_Length(ST_Intersection(a.geom, b.geom)) > 0)
), maxes AS (
	SELECT
		small_gid,
		MAX(touch_length) AS max_length,
		MAX(large_area) AS max_area
	FROM ungrouped
	GROUP BY (small_gid)
),
scores AS (
	SELECT
		ungrouped.small_gid,
		ungrouped.large_gid,
		-- formula to determine best neighbor for merging
		100 * ungrouped.touch_length / maxes.max_length +
			1 * ungrouped.large_area / maxes.max_area AS score
	FROM ungrouped
	JOIN maxes
	ON maxes.small_gid = ungrouped.small_gid
),
max_scores AS (
	SELECT small_gid, MAX(score) AS score
	FROM scores
	GROUP BY small_gid
),
merging_gids AS (
	SELECT
		scores.small_gid,
		MIN(scores.large_gid) AS large_gid
	FROM scores
	JOIN max_scores
	ON scores.small_gid = max_scores.small_gid
	WHERE scores.score = max_scores.score
	-- 	ensure small geometry is only merged once
	GROUP BY scores.small_gid
),
merged_polys AS (
	SELECT
		l.gid AS large_gid,
		ST_Union(l.geom || array_agg(s.geom)) AS geom
	FROM merging_gids AS mg
	LEFT JOIN flat_parcels l
	ON l.gid = mg.large_gid
	LEFT JOIN flat_parcels s
	ON s.gid = mg.small_gid
	GROUP BY l.gid, l.geom
)
SELECT
	fp.gid,
	CASE
		WHEN mp.large_gid IS NOT NULL
			THEN mp.geom
		ELSE
			fp.geom
	END
INTO parcels_merged
FROM flat_parcels AS fp
LEFT JOIN merged_polys AS mp
ON fp.gid = mp.large_gid
LEFT JOIN merging_gids AS s
ON fp.gid = s.small_gid
-- drop small polygons
WHERE s.small_gid IS NULL;


-- Simplify geometries where points are closer than 0.5 feet
SELECT
	gid,
	pins,
	ST_Simplify(geom, 0.5) AS geom
INTO parcels_reduced_simplified_05
FROM parcels_reduced;

CREATE INDEX parcels_reduced_simplified_05_idx
ON parcels_reduced_simplified_05
USING GIST(geom);


-- Create clusters of close points
WITH dumped_pts AS (
	SELECT
		gid, (ST_DumpPoints(geom)).*
	FROM parcels_reduced_simplified_05
	ORDER BY gid
),
grouped_dumped_pts AS (
	SELECT
		array_agg(gid || path) AS paths,
		geom
	FROM dumped_pts
	GROUP BY geom
),
pt_clusters AS (
	SELECT
		unnest(ST_ClusterWithin(geom, 0.4)) AS geom
	FROM grouped_dumped_pts
)
SELECT geom
INTO clustered_pts
FROM pt_clusters
WHERE ST_NumGeometries(geom) > 1;


-- Replace clustered points with centroid of cluster
ALTER TABLE clustered_pts ADD COLUMN centroid geometry(Geometry,2272);
UPDATE clustered_pts SET centroid = ST_Centroid(clustered_pts.geom);

ALTER TABLE clustered_pts
ADD COLUMN cluster_id integer primary key generated always as identity;


-- get multipolygons with multiple polygons and holes
WITH dumped_polys AS (
	SELECT
		gid, (ST_Dump(geom)).geom
	FROM parcels_reduced_simplified_05
)
SELECT gid, ST_Collect(geom)
FROM dumped_polys
WHERE ST_NumInteriorRings(geom) > 0
GROUP BY gid
HAVING COUNT(*) > 1
LIMIT 2;


-- Snapping polygon points to clusters!
SET max_parallel_workers = 8;
SET max_parallel_workers_per_gather = 4;

SELECT
	centroid,
	(ST_Dump(geom)).geom AS original_pt
INTO flat_clusters
FROM clustered_pts;

CREATE INDEX flat_clusters_idx ON flat_clusters USING GIST(original_pt);


SELECT
	gid,
	(ST_DumpPoints(geom)).*
INTO prs_05_dumped_pts
FROM parcels_reduced_simplified_05;

CREATE INDEX prs_05_dumped_pts_idx ON prs_05_dumped_pts USING GIST(geom);

WITH replaced_pts AS
(
	SELECT
		dp.gid,
		dp.path,
		CASE
			WHEN fc.original_pt IS NOT NULL
				THEN fc.centroid
			ELSE dp.geom
		END AS geom
	FROM prs_05_dumped_pts AS dp
	LEFT JOIN flat_clusters fc
	-- ST_DWithin is MUCH faster than ST_Equals
	ON ST_DWithin(dp.geom, fc.original_pt, 0.0)
),
replaced_pts_ordered AS (
	SELECT
		gid,
		-- 	polygons    per multipolygon
		path[1] AS poly_id,
		-- 	linestrings per polygon 
		path[2] AS ls_id,
		-- 	points      per linestring
		path[3] AS pt_id,
		geom
	FROM replaced_pts
	ORDER BY
		gid,
		path[1],
		path[2],
		path[3]
),
ls_flat AS (
	SELECT
		gid,
		-- 	polygons per multipolygon
		poly_id,
		-- 	linestrings per polygon 
		ls_id,
		ST_MakeLine(array_agg(geom)) AS geom
	FROM replaced_pts_ordered
	GROUP BY
		gid,
		poly_id,
		ls_id
	ORDER BY
		gid,
		poly_id,
		ls_id
),
ls_arrs AS (
	SELECT
		gid,
		poly_id,
		array_agg(geom) AS arr
	FROM ls_flat
	GROUP BY
		gid,
		poly_id
	ORDER BY
		gid,
		poly_id
),
polys AS (
	SELECT
		gid,
		poly_id,
		ST_MakePolygon(arr[1], arr[2:]) AS geom
	FROM ls_arrs
)
SELECT
	gid,
	ST_MakeValid(ST_Collect(array_agg(geom))) AS geom
INTO snapped_parcels
FROM polys
GROUP BY gid;


-- breaks multipolygons into segments
-- https://gis.stackexchange.com/questions/174472/in-postgis-how-to-split-linestrings-into-their-individual-segments
WITH dumped_linestrings AS (
	SELECT
		ST_Boundary((ST_Dump(geom)).geom) AS geom
	FROM snapped_parcels
	WHERE geom IS NOT NULL
),
numbered_linestrings AS (
	SELECT
		ROW_NUMBER () OVER () AS id,
		geom
	FROM dumped_linestrings
),
line_counts AS (
	SELECT
		ST_NPoints(geom) - 1 AS cts,
		id
	FROM numbered_linestrings
),
series AS (
	SELECT
		generate_series(1, cts) AS num,
		id
	FROM line_counts
),
segments AS (
	SELECT
		ST_MakeLine(
			ST_PointN(geom, num), 
			ST_PointN(geom, num + 1)
		) as geom
	FROM series 
	INNER JOIN numbered_linestrings
	ON series.id = numbered_linestrings.id
),
normalized_segments AS (
	SELECT ST_Normalize(geom) AS geom
	FROM segments
	WHERE geom IS NOT NULL
)
SELECT DISTINCT geom
INTO snapped_parcel_segments
FROM normalized_segments;


-- splits segments at intersections
-- takes about 3 minutes
WITH temp_split_segs AS (
	SELECT
		a.gid,
		ST_Collect(b.geom) AS geom
	FROM snapped_parcel_segments a
	LEFT JOIN snapped_parcel_segments b
	ON ST_Crosses(a.geom, b.geom)
	WHERE a.gid <> b.gid
	GROUP BY a.gid
)
SELECT (ST_Dump(
	CASE
		WHEN tss.gid IS NULL
			THEN sps.geom
		ELSE tss.geom
	END)).geom
INTO snapped_parcel_segments_split
FROM snapped_parcel_segments sps
LEFT JOIN temp_split_segs tss
ON sps.gid = tss.gid;


-- POLYGONIZE
-- This seems slow?
-- Why single threaded?
-- GEOS alternative? Shapely, PyGeos, etc?
-- Is ST_Node doing the heavy lifting?
-- Why is it necessary to collect the segments before making nodes?
-- (It works partially without collecting, but only some polygons are created)
-- Is it possible to skip segment creation entirely and just use
-- the boundary linestrings from the multipolygons?
WITH nodes AS (
	SELECT ST_Node(ST_Collect(geom)) AS node
	FROM snapped_parcel_segments_split
)
SELECT (ST_Dump(ST_Polygonize(node))).geom
INTO snapped_parcels_polygonized
FROM nodes;


-- Find parcels with most overlaps for quick experimentation
SELECT
	a.gid,
	COUNT(*),
	ST_Collect(a.geom || array_agg(b.geom))
FROM parcels AS a
JOIN parcels AS b
ON ST_Intersects(a.geom, b.geom)
WHERE a.gid <> b.gid
AND (
	ST_Overlaps(a.geom, b.geom)
	OR ST_Contains(a.geom, b.geom)
	OR ST_Within(a.geom, b.geom)
)
GROUP BY a.gid
ORDER BY COUNT(*) DESC;
