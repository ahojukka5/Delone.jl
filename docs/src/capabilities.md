# Wrapped capabilities

Bindings live in `NetgenCxxWrap_jll` (`libnetgen_cxxwrap`) and are loaded by
`Netgen.jl`. C++ names are preserved 1:1; the sections below group them by
workflow. For per-class method lists see `docs/API_COVERAGE.md` in the package
tree.

## Geometry input

| Capability | Julia / C++ entry points |
|------------|--------------------------|
| STEP / IGES / BREP import | `load_step`, `load_iges`, `load_brep`, `load_geometry` → `LoadOCC_*` |
| STL import | `load_stl` → `LoadSTL` |
| 2D spline geometry file | `load_splinegeometry2d` |
| 2D CSG | `Circle`, `Rectangle`, `CSG2d`, `geometry2d`, boolean `+` / `*` / `-` |
| OCC programmatic 3D | `Netgen.OCC`: `BRepPrimAPI_*`, `BRepBuilderAPI_*`, `BRepAlgoAPI_*`, `OCCGeometry` |
| OCC I/O | `BRepTools_Read/Write`, `STEPControl_*`, `IGESControl_*` |

## Mesh generation & core `Mesh` API

| Capability | Entry points |
|------------|--------------|
| Generate from geometry | `generate_mesh`, `MeshingParameters`, `maxh!`, `NetgenGeometry.GenerateMesh` |
| Node / element access | `GetNP`, `Point`, `VolumeElement`, `SurfaceElement`, `LineSegment`, `GetNE`, `GetNSE`, `GetNSeg`, `GetDimension` |
| Build / modify mesh | `AddPoint`, `AddVolumeElement`, `AddSurfaceElement`, `AddSegment`, `assign` (`copy_mesh`) |
| Topology | `UpdateTopology`, `GetTopology`, `GetNEdges`, `GetNFaces`, `GetEdgeVertices`, `GetFaceVertices`, `EnableTopologyTable` |
| Quality / h-field | `CalcLocalH`, `SetGlobalH`, `ImproveMesh`, `CheckVolumeMesh`, `GetBox`, `AverageH`, … |
| Mesh I/O | `Save`, `Load` |
| Sub-mesh extraction | `GetSubMesh` |

## Refinement (geometry-aware)

| Capability | Entry points |
|------------|--------------|
| Uniform refine | `refine!` → `Refinement.Refine` |
| Marked bisection | `mark_for_refinement!`, `bisect!` → `BisectionOptions`, `Refinement.Bisect` |
| Second-order curving | `make_second_order!` → `Refinement.MakeSecondOrder` |
| Volume meshing driver | `MeshVolume`, `OptimizeVolume`, `RemoveIllegalElements`, `ConformToFreeSegments` |

## `Ngx_Mesh` hierarchy & parent maps

| Capability | Entry points |
|------------|--------------|
| Multigrid levels | `num_levels`, `level_nvertices`, `Ngx_Mesh.GetNLevels`, `GetNVLevel` |
| Prolongation stencil | `parent_nodes`, `parent_elements`, `parent_surface_elements`, `GetParentNodes`, … |
| Curved geometry on mesh | `Curve`, `GetCurveOrder`, `BuildCurvedElements` |
| Copy / nested hierarchy helpers | `copy_mesh`, `MeshHierarchy`, `coarse_hierarchy`, `uniform_hierarchy`, `refine_uniform!` |

## Live session & snapshots (Julia layer)

| Capability | Description |
|------------|-------------|
| `MeshHierarchySession`, `mesh_session` | Authoritative live handles per level + `generation` counter |
| `request_uniform_refinement!`, `request_marked_refinement!`, `request_second_order!` | Append levels or in-place curving |
| `MeshLevelSnapshot`, `HierarchyTransferSnapshot`, `MeshHierarchySnapshot` | **Copied** mesh data for downstream consumers |
| `supported_snapshot_topology`, `transfer_weight_semantics` | Documented snapshot contract |

## hp-adaptivity (read + apply)

| Capability | Entry points |
|------------|--------------|
| Read orders / hp levels | `element_order(s)`, `element_orders_xyz`, `surface_element_orders`, `hp_element_levels` |
| Cluster representatives | `cluster_rep_*` (requires `hp_clusters_available`) |
| Apply p / hp | `set_element_order!`, `set_element_orders!`, `ngx_refine!`, `hp_refine!`, `split_alfeld!` |
| Session requests | `request_set_element_orders!`, `request_marked_p_refinement!`, `request_hp_refine!`, … |
| Constants | `NG_REFINE_H`, `NG_REFINE_P`, `NG_REFINE_HP` |

## Tags, regions & names

| Capability | Entry points |
|------------|--------------|
| Bulk extraction | `volume_tetrahedra`, `surface_triangles`, `triangles2d`, `segments2d` |
| Region ids per cell/facet | `cell_regions`, `boundary_regions` |
| Name dictionaries | `material_names`, `boundary_names` (3D reliable; 2D limitations documented) |
| Per-element names | `region_name_volume`, `region_name_surface`, `region_name_segment` |
| Codimension names | `material_codim_name`, `GetMaterialCD0`–`3` |

## FEM geometry & partition hints

| Capability | Entry points |
|------------|--------------|
| Curved element maps | `volume_element_transformation`, `surface_element_transformation`, `domain_element_transformation`, `MultiElementTransformation*` |
| Parent edge/face maps | `enable_topology_table!`, `has_parent_edges`, `parent_edges`, `parent_faces`, `face_edges` |
| Periodic pairs | `periodic_vertex_pairs`, `GetPeriodicVertices` |
| Partition hints | `native_partition_hint` → `GetGlobalVertexNum`, `GetDistantProcs` |
| Point location | `find_element`, `FindElementOfPoint1/2/3` |
| Mesh size at node | `mesh_h_at_point`, `GetHPointIndex` |

## Julian extraction helpers

| Function | Returns |
|----------|---------|
| `points` | `3×GetNP` coordinates |
| `tetrahedra` | `4×GetNE` volume connectivity (3D) |
| `surface_triangles` | boundary triangles (3D) or domain triangles (2D) |
| `prolongation` | sparse-style parent data between hierarchy levels |

## OpenCASCADE (`Netgen.OCC`)

Wrapped at **modeling-kernel** scope (not full OCCT):

- **gp_*** value types (points, axes, transforms, lines, circles, planes, quadrics, …)
- **TopoDS_*** shapes + `TopExp_Explorer`, `TopoDS_Iterator`, `TopTools_IndexedMapOfShape`
- **BRepPrimAPI_*** primitives, **BRepBuilderAPI_*** construction, **BRepAlgoAPI_*** booleans
- **BRepFilletAPI_***, **BRepOffsetAPI_*** (thick solid, pipe, draft, …)
- **GProp_***, **Bnd_***, **BRepGProp_***, **BRepBndLib_***
- **ShapeFix_***, **ShapeAnalysis_***, **BRepCheck_***, **BRepMesh_IncrementalMesh**
- **Geom_Curve/Surface** handles, **GeomAPI_*** projection/extrema
- Bridge: `OCCGeometry(shape)` → Netgen meshable geometry

See `docs/API_COVERAGE.md` in the package tree for per-class OCCT counts.

## Test coverage

The package test suite (`test/runtests.jl`, 790+ tests) exercises mesh core, OCC
modeling, 2D CSG, refinement, hierarchy, session/snapshots, hp apply, FEM helpers,
and tags/partition contracts against local fixtures (`test/fixtures/`).
