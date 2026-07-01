# Netgen.jl

A **CxxWrap-based Julia binding for the exported C++ API of NGSolve/Netgen**,
plus a thin Julia layer for building geometry-backed, refinable mesh hierarchies.

The native bindings come from `NetgenCxxWrap_jll` (`libnetgen_cxxwrap`, a CxxWrap
module that wraps Netgen's C++ API 1:1). This package loads it via
`CxxWrap.@wrapmodule`/`@initcxx` and adds idiomatic helpers. Geometry can come
from a CAD file (STEP/IGES/BREP), be built programmatically with OpenCASCADE
(`Netgen.OCC`), or be defined in 2D (`geom2d`/`csg2d`). Refinement is
**geometry-aware**: new boundary nodes are projected onto the true curved
surface.

> Transfer operators for geometric multigrid are **not** built here — this
> package exposes the meshes and the topological coarse→fine **mapping**
> (`parent_nodes` / `prolongation`); assembling prolongation/restriction
> operators is left to the consumer.

## Stack

```
NGSolveNetgen_jll   upstream NGSolve/Netgen binary (+ OpenCASCADE)
NetgenCxxWrap_jll   libnetgen_cxxwrap: boring 1:1 CxxWrap wrapper of Netgen's C++ API
Netgen.jl           this package — Julian conveniences + hierarchy/mapping helpers
```

## Example: refine a 2D disk and read the mesh hierarchy

Mesh a unit disk coarsely, then refine it. New boundary nodes snap onto the true
circle, and `parent_nodes` tells us, for every fine node, which two coarse nodes
it came from — the topological link between the two meshes.

```julia
using Netgen

# A unit disk (radius 1) built programmatically; its boundary is a true circle.
disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
geom = geometry2d(disk)

# 1. Coarse mesh.
coarse = generate_mesh(geom; maxh=0.5)
Xc = points(coarse)                       # 2×np coordinates

# 2. Refine (geometry-aware). copy_mesh keeps `coarse` intact as its own level.
fine = copy_mesh(coarse)
refine!(fine)
Xf = points(fine)

# 3. Hierarchical mapping between the two meshes.
#    parent_nodes(fine)[:, j] gives the two coarse nodes that fine node j came
#    from, or (0, 0) if node j already existed on the coarse mesh (with the
#    SAME index there — coarse vertices keep their numbering in every level).
P = parent_nodes(fine)
radius(p) = hypot(p[1], p[2])

for j in axes(P, 2)
    a, b = P[1, j], P[2, j]
    a == 0 && continue                    # inherited: Xf[:, j] == Xc[:, j]
    # New node: it descends from the coarse edge (a, b). On a curved boundary it
    # is the edge's midpoint *projected onto the geometry*, not the plain average.
    midpoint = (Xc[:, a] .+ Xc[:, b]) ./ 2
    # e.g. on the circle: parents at radius 1, midpoint inside (r<1), node on r=1.
end
```

Running it on a coarse disk:

```
coarse: 19 nodes, 24 triangles
fine:   61 nodes, 96 triangles
new boundary node 20: parents (1, 5)
  parent radii:     1.0, 1.0
  chord midpoint r: 0.965926   (inside the disk)
  actual node r:    1.0         (snapped onto the circle)
inherited nodes: 19  (== coarse node count)
```

A new boundary node is *not* the plain average of its parents — it is projected
onto the curved boundary. The parents sit at radius 1, their chord midpoint is
inside (radius `< 1`), but the actual node is placed back on the circle at radius
exactly 1. That is what "geometry-aware" means, and it keeps every level of the
hierarchy faithful to the CAD model. The 19 inherited nodes keep their indices,
so `parent_nodes` is all that is needed to relate the two meshes.

## Building geometry

```julia
# CAD files
geom = load_step("model.step")          # also load_brep / load_iges
geom = load_geometry("model.brep")      # dispatch on extension

# OpenCASCADE modeling kernel, wrapped 1:1 (Netgen.OCC submodule — raw OCCT
# class names, no helpers). Build a TopoDS_Shape, then wrap it as a geometry.
using Netgen.OCC
ax    = gp_Ax2(gp_Pnt(0.0,0.0,0.0), gp_Dir(0.0,0.0,1.0))
shape = Shape(BRepPrimAPI_MakeCylinder(ax, 1.0, 2.0))    # also MakeBox/MakeSphere/...
cut   = Shape(BRepAlgoAPI_Cut(shape,
              Shape(BRepPrimAPI_MakeSphere(gp_Pnt(0.0,0.0,0.0), 0.6))))  # booleans
geom  = OCCGeometry(cut)                                  # -> meshable geometry

# 2D CSG (geom2d): Circle / Rectangle with boolean ops + - *
plate = Rectangle(-1.0,-1.0, 1.0,1.0, "plate", "outer")
hole  = Circle(0.0, 0.0, 0.4, "hole", "inner")
geom  = geometry2d(plate - hole)        # plate with a circular hole
```

## Mesh access and refinement

```julia
mesh = generate_mesh(geom; maxh=0.2)

points(mesh)             # dim×np Matrix{Float64}
tetrahedra(mesh)         # 4×ne Matrix{Int32}, 1-based (3D volume meshes)
surface_triangles(mesh)  # 3×nse Matrix{Int32}, 1-based (boundary / 2D meshes)

refine!(mesh)                                   # uniform, geometry-aware, in place
mark_for_refinement!(mesh, marked); bisect!(mesh)  # adaptive, element-wise

# Material / boundary labels (Element/Element2d GetIndex -> name)
Netgen.GetMaterial(mesh, 1)
Netgen.GetBCName(mesh, 1)
```

## Mesh hierarchy

A growable stack of nested meshes sharing one geometry. Grow it during a
simulation — uniformly or by an error indicator — and read the per-level mapping.

```julia
h = coarse_hierarchy(geom; maxh=0.5)    # level 1
refine_uniform!(h)                      # push a uniformly refined level
refine_marked!(h, marked)               # push an adaptively refined level

nlevels(h)                              # number of levels
coarsest(h); finest(h)
prolongation(h, k)                      # 2×np mapping from level k-1 to level k
                                        # (== parent_nodes(h[k]))

# or build all uniform levels up front:
h = uniform_hierarchy(geom; maxh=0.5, levels=4)
```

Wrapped Netgen names are available directly (`Netgen.GetNP`, `Netgen.GetNE`,
`Netgen.UpdateTopology`, `Netgen.GetTopology`, `Netgen.Refinement`,
`Netgen.MeshingParameters`, …); the exported Julian layer composes them.

## Live session + snapshots (consumer integration contract)

Netgen.jl exposes the geometry-backed mesh hierarchy as a **live session** — the
authoritative state a solver keeps during a simulation — plus **copied
snapshots** for consumers. The two are distinct on purpose: the live Netgen mesh
handles are authoritative; snapshots are derived copies.

### Live session / handles

Authoritative Netgen state that supports refinement requests *during* a
simulation. Every mutating request (`request_*!`) bumps `generation(session)` and
appends a new level while preserving access to all previous levels.

```julia
s = mesh_session(geom; maxh=0.5)     # level 1; generation 0
nlevels(s)                           # 1
finest(s); coarsest(s)               # live Netgen mesh handles
level_mesh(s, k)                     # live handle for level k (authoritative)
geometry(s); generation(s)

# grow the live hierarchy as the solve/adapt loop proceeds:
request_uniform_refinement!(s)                # append a uniformly refined level
request_marked_refinement!(s, marked)         # append an adaptively bisected level
request_second_order!(s)                       # curve finest IN PLACE (no new level)
```

`request_marked_refinement!` takes `marked` indexed by the **current finest
level's** volume elements. `request_second_order!` curves the current finest mesh
in place (a p-type change to the same h-level), it does **not** append a level.

### Snapshots

Copied, consumer-agnostic plain arrays. Mutating a snapshot never touches the
live handles.

```julia
ls = level_snapshot(s, k)     # coordinates, volume/boundary connectivity,
                              # cell_regions, boundary_regions, material_names,
                              # boundary_names, element types, level, generation
ts = transfer_snapshot(s, k)  # parent_nodes/elements/surface_elements for k-1 → k
                              # (transfer_snapshot(s, 1) throws ArgumentError)
hs = hierarchy_snapshot(s)    # all levels + all transfers + generation
```

`transfer_snapshot(...).weights === nothing`: exact interpolation weights are not
yet provided — a consumer should start with **topological 1/2–1/2 nodal
interpolation** on the bisection parent-node map.

### Stable identity convention

All snapshot ids are **one-based**; `0` means "none". Parent-node columns of
`(0, 0)` mark an **inherited** coarse vertex, and inherited coarse vertices keep
their id on refined levels (so `coords(coarse) ≈ coords(fine)[:, 1:np_coarse]`).
This holds for the current construction path (each level refines a copy of the
previous finest level). See
[`audit/NETGEN_LIVE_HIERARCHY_AND_PARTITION_CONTRACT_2026-07-01.md`](audit/NETGEN_LIVE_HIERARCHY_AND_PARTITION_CONTRACT_2026-07-01.md).

### Tags, regions, hp-readiness

```julia
volume_tetrahedra(mesh); surface_triangles(mesh)   # 3D
triangles2d(mesh); segments2d(mesh)                # 2D (dimension-checked)
cell_regions(mesh); boundary_regions(mesh)         # Netgen GetIndex region ids
material_names(mesh); boundary_names(mesh)          # region id → name

element_orders(mesh); element_order(mesh)           # p-order readers (read-only)
surface_element_orders(mesh); surface_element_order(mesh)
hp_element_levels(mesh)                              # 3×ncells, -1 = not hp-refined
```

hp helpers are **read-only readiness**: a consumer can ask what orders/hp-levels
exist. Applying per-element p-refinement needs Netgen's exported order *setters*
wrapped 1:1 (not done yet — see the audit doc).

### Integration contract

```
Netgen.jl owns   geometry-backed mesh hierarchy handles, refinement requests,
                 parent maps, stable ids, region/tag + hp-readiness data,
                 and copied snapshots.
Consumer owns    FE spaces, DOF numbering, matrix-free operators, error
                 estimators, preconditioners, GMG assembly, domain
                 decomposition, dynamic load balancing, and migration.
```

### Partitioning responsibility

```
Netgen.jl provides   geometry-backed mesh levels, parent maps, stable ids,
                     region/tag data, and optional raw partition hints if
                     available (native_partition_hint(mesh)).
Consumer provides    PartitionGraph, cell/edge weights, METIS/ParMETIS backend
                     selection, PartitionAssignment, distributed ownership,
                     ghost/halo construction, dynamic repartitioning + migration.
```

Netgen.jl does **not** call METIS/ParMETIS and does **not** own partition policy.
`native_partition_hint(mesh)` currently returns `nothing`: Netgen's partition
data (`GetDistantProcs`, `GetGlobalVertexNum`) is MPI-only and the bound artifact
is serial, so there is no native serial partition array to expose (documented,
not invented).

## Status

Wrapped and tested locally: module load + value types, mesh core + extraction,
OCC import (STEP/IGES/BREP) **and** the OpenCASCADE modeling kernel wrapped 1:1
(`gp_*`, `TopoDS_*`, `BRepPrimAPI_*`, `BRepBuilderAPI_*`, `BRepAlgoAPI_*`,
`TopExp_Explorer`, `BRepTools`, `STEPControl`/`IGESControl`, `OCCGeometry`), 2D
geom2d/csg2d (circle/rectangle + boolean CSG), geometry-aware uniform **and**
adaptive (marked-bisection) refinement, second-order curving, material/BC labels,
the `Ngx_Mesh` multigrid hierarchy (levels + parent maps), mesh copy, and nested
hierarchies. Verified on a curved unit cylinder/disk/sphere that refined nodes
land exactly on the surface. The wrapped OCC surface is the modeling kernel; the
~6500 internal OCCT headers (STEP/IGES schema, visualization, meshing internals)
are out of scope. See `NetgenCxxWrap_jll/docs/WRAPPING_PLAN.md` for the full list.

## Development

`NetgenCxxWrap_jll` isn't registered yet, so the native library is built locally
and bound via `Artifacts.toml`:

```
julia --project=Netgen.jl Netgen.jl/gen/build_local.jl
```

This compiles `libnetgen_cxxwrap` against the locally-bound NGSolveNetgen
artifact + OCCT_jll + the CxxWrap/JlCxx prefix (this platform only). Then
`pkg> test Netgen`.
