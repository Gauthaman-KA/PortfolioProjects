select * from building_points;

alter table building_points drop column notes;

--Total no of damaged buildings
select siteid,count(*) from building_points group by siteid;

--Types of buildings damaged
select siteid,main_damag,count(*) from building_points group by siteid,main_damag order by siteid;

--Total buildings damaged based on severity
select main_damag,count(*) from building_points group by main_damag;

--Destroyed Buildings View
DROP VIEW IF EXISTS DestroyedBuildings;
CREATE OR REPLACE VIEW
DestroyedBuildings AS
SELECT ogc_fid,wkb_geometry FROM building_points where (main_damag = 'Destroyed');

--Moderately damaged Buildings View
DROP VIEW IF EXISTS ModeratelyDamaged;
CREATE OR REPLACE VIEW
ModeratelyDamaged AS
SELECT ogc_fid,wkb_geometry FROM building_points where (main_damag = 'Moderate Damage');

--Severely damaged Buildings View
DROP VIEW IF EXISTS SeverelyDamaged;
CREATE OR REPLACE VIEW
SeverelyDamaged AS
SELECT ogc_fid,wkb_geometry FROM building_points where (main_damag = 'Severe Damage');

--
select * from buildings_polygons;

SELECT B.ogc_fid,count(*)
FROM buildings_polygons as B, building_points as P
WHERE (P.grouped = 'Damaged Buildings') and (ST_Distance(B.wkb_geometry,P.wkb_geometry) != 0) 
and (ST_Distance(B.wkb_geometry,P.wkb_geometry) <=500 ) group by B.ogc_fid


ALTER TABLE buildings_polygons DROP COLUMN  IF EXISTS BuildingCount;
ALTER TABLE buildings_polygons ADD COLUMN BuildingCount Numeric DEFAULT 0;

With PolygonQuery as (
SELECT B.ogc_fid,count(*) as BuildingsCount
FROM buildings_polygons as B, building_points as P
WHERE (P.grouped = 'Damaged Buildings') and (ST_Distance(B.wkb_geometry,P.wkb_geometry) != 0)
and (ST_Distance(B.wkb_geometry,P.wkb_geometry) <=500 ) group by B.ogc_fid
)
UPDATE buildings_polygons
SET BuildingCount = CAST(PolygonQuery.BuildingsCount AS numeric)
FROM PolygonQuery 
WHERE buildings_polygons.ogc_fid = PolygonQuery.ogc_fid;


--Building Polygons with no nearby war damaged buildings within 500 Meters Radius
select count(*) from buildings_polygons where (buildingcount=0);

--Building Polygons with nearby war damaged buildings within 500 Meters
select ogc_fid,buildingcount from buildings_polygons where (buildingcount>0) order by buildingcount;

--Building Polygon with most damaged buildings within 500 Meters
select ogc_fid,buildingcount from buildings_polygons order by buildingcount desc limit 1;


--
select * from poi_points;

--Buffer Analysis of impact area around completely destroyed buildings
--Add buffer geom column in the buildings table
DROP TABLE IF EXISTS BuildingsBuffer; 

create table BuildingsBuffer as
	select ogc_fid,main_damag,siteid, ST_Buffer(wkb_geometry,200.0) as BufferGeom
	from building_points where (main_damag = 'Destroyed');

ALTER TABLE BuildingsBuffer ADD PRIMARY KEY (ogc_fid);

CREATE INDEX "BuildingsBuffer_geom_idx" ON BuildingsBuffer 
USING GIST (BufferGeom);

--Buildings Polygons Buffer Analysis
select distinct ogc_fid  from
(
	select
		buildP.ogc_fid,
		(BBuffer.BufferGeom <-> buildP.wkb_geometry) as DistanceToBuffer,
		BBuffer.ogc_fid as BuildingBufferID,
		rank() over (partition by buildP.ogc_fid order by
		BBuffer.BufferGeom <-> buildP.wkb_geometry asc) as DistanceRank
	from
		BuildingsBuffer as BBuffer,
		buildings_polygons as buildP
) as BufferQueryResults
where BufferQueryResults.DistanceRank = 1 and BufferQueryResults.DistanceToBuffer = 0 ;
-- 30 Building Polygons are within the buffer region of the Destroyed Buildings, which means these buildings were in 
--the vicinity of destroyed buildings.

--Points of Interests Buffer Analysis
select distinct ogc_fid from
(
	select
		points.ogc_fid,
		(BBuffer.BufferGeom <-> points.wkb_geometry) as DistanceToBuffer,
		BBuffer.ogc_fid as BuildingBufferID,
		rank() over (partition by points.ogc_fid order by
		BBuffer.BufferGeom <-> points.wkb_geometry asc) as DistanceRank
	from
		BuildingsBuffer as BBuffer,
		poi_points as points
) as BufferQueryResults
where BufferQueryResults.DistanceRank = 1 and BufferQueryResults.DistanceToBuffer = 0 ;

-- 46 Points of Interests are within the buffer region of the Destroyed Buildings, which means these buildings were in 
--the vicinity of destroyed buildings.