# Geometry

Loading and constructing geometry (CAD import and 2D constructive solid
geometry) prior to meshing.

```@docs
load_step
load_iges
load_brep
load_geometry
load_stl
load_splinegeometry2d
geometry2d
Circle
Rectangle
CSG2d
occ_geometry_from_brep_string
```

## Periodic boundary conditions

Pre-mesh OCC face identification for periodic boundary conditions
(computational homogenization / RVE unit cells) — see
[Building geometry](@ref "Building geometry") for a worked example.

```@docs
occ_nr_faces
occ_face_bbox
faces_on_plane
identify_periodic!
identify_periodic_box!
```
