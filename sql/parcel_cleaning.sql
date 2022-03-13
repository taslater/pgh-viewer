-- select a region with many overlapping polygons
WITH sub_parcels AS (
	SELECT *
	FROM parcels
	WHERE ST_Within(
		geom,
		ST_MakeEnvelope(
			1340261,
			411622,
			1341132,
			412362,
			2272
		)
	)
),
-- explode every point from the polygons
dump_pts AS (
	SELECT
		(ST_DumpPoints(geom)).geom
	FROM sub_parcels
),
-- cluster points that are within 1 foot of each other
pt_clusters AS (
	SELECT unnest(ST_ClusterWithin(geom, 1)) AS geom
	FROM dump_pts
),
-- get the centroid of each cluster for snapping
pt_clusters_unnested AS (
	SELECT
		ROW_NUMBER() OVER () AS cluster_id,
		ST_NumGeometries(geom) AS cluster_size,
		ST_Centroid(geom) AS centroid,
		geom
	FROM pt_clusters
),
-- explode each point cluster
pt_clusters_flat AS (
	SELECT
		cluster_id,
		cluster_size,
		centroid,
		(ST_Dump(geom)).geom AS geom
	FROM pt_clusters_unnested
)
-- calculate the distance of each cluster point to its centroid
SELECT
	*,
	ST_Distance(centroid, geom) AS d_to_centroid
FROM pt_clusters_flat
ORDER BY ST_Distance(centroid, geom) DESC;


-- polygonize (flatten) fast and easy
-- PostGIS ST_Node() seems slow
SET max_parallel_workers = 8;
SET max_parallel_workers_per_gather = 4;

WITH unioned AS (
	SELECT ST_Union(ST_Boundary(geom)) AS geom
	FROM parcels_fixed
)
SELECT (ST_Dump(ST_Polygonize(geom))).geom
INTO parcels_polygonized_2
FROM unioned;