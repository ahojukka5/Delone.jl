# Building geometry

Delone.jl accepts geometry from files, 2D constructive solid geometry (CSG), or
shapes built in [OpenCascade.jl](https://github.com/ahojukka5/Monge.jl) and passed via BREP strings.

## Import CAD files

```@example geometry
using Delone

frame_step    = joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "frame.step")
cylinder_brep = joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "cylinder.brep")
tet_stl       = joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "tet.stl")

step_geom = load_step(frame_step)          # also load_iges, load_brep
brep_geom = load_geometry(cylinder_brep)   # extension dispatch

# STL → surface mesh pipeline (3D triangle soup)
stl_geom = load_stl(tet_stl)

(typeof(step_geom), typeof(brep_geom), typeof(stl_geom))
```

`load_*` functions return a Netgen geometry object (`NetgenGeometry` /
`STLGeometry`) that you pass to `generate_mesh` (see [Meshing](@ref "Meshing")).

## 2D CSG — disks, rectangles, booleans

2D domains use `geom2d` / `csg2d`. Primitives carry a material label and a
boundary label:

```@example geometry
# Unit disk (radius 1), curved boundary
disk = Circle(0.0, 0.0, 1.0, "disk", "outer")
disk_geom = geometry2d(disk)

# Plate with a rectangular notch (difference)
outer = Circle(0.0, 0.0, 1.0, "plate", "circle")
notch = Rectangle(-0.2, -1.5, 0.2, 0.0, "notch", "rect")
plate_geom = geometry2d(outer - notch)

# Union / intersection: use + and * ; difference: -
(typeof(disk_geom), typeof(plate_geom))
```

Boolean operators match Netgen's CSG conventions (`+` union, `*` intersection,
`-` difference).

## 3D modeling with OpenCascade.jl

CAD modeling lives in **OpenCascade.jl** (not Delone). Build a shape there, then
import via the in-memory BREP boundary:

<!-- not converted to @example: OpenCascade.jl is a separate package and is not
     a dependency of docs/Project.toml, so `using OpenCascade` cannot execute
     during the docs build. -->
```julia
using OpenCascade, Delone

body = cylinder(1.0, 2.0)
geom = occ_geometry_from_brep_string(to_brep_string(body))
mesh = generate_mesh(geom; maxh=0.3)
```

### Booleans

<!-- not converted to @example: depends on OpenCascade.jl (see above), which is
     not available in the docs build environment. -->
```julia
big   = box(2, 2, 2)
small = sphere(0.6; center=Point(1, 1, 1))
result = subtract(big, small)
geom   = occ_geometry_from_brep_string(to_brep_string(result))
```

### File export / Netgen file import

<!-- not converted to @example: `body` comes from the unexecuted OpenCascade.jl
     snippet above, and OpenCascade.jl is not a docs dependency. -->
```julia
write_brep(body, "part.brep")
geom = load_brep("part.brep")
```

## Periodic boundary conditions (RVE / microstructure unit cells)

For computational homogenization (RVE) modeling, opposite faces of a unit
cell need matching mesh nodes so a downstream solver can tie DOFs across the
periodic boundary. [`identify_periodic_box!`](@ref) sets this up for the
common axis-aligned box/hex case: it finds the min- and max-face along an
axis and registers a pre-mesh periodic identification between them, so
Netgen builds the second face's mesh as an exact copy of the first (no
interpolation error).

<!-- not converted to @example: depends on OpenCascade.jl (see above), which
     is not available in the docs build environment. -->
```julia
using OpenCascade, Delone

geom = occ_geometry_from_brep_string(to_brep_string(box(1, 1, 1)))
geom = identify_periodic_box!(geom, :x; name="periodic_x")
geom = identify_periodic_box!(geom, :y; name="periodic_y")
geom = identify_periodic_box!(geom, :z; name="periodic_z")
mesh = generate_mesh(geom; maxh=0.3)

# verify: node pairs on opposite x-faces differ by exactly (1,0,0)
pairs = periodic_vertex_pairs(mesh, 1)
```

Periodic identification must be set up **before** `generate_mesh` — see
[`identify_periodic!`](@ref)'s docstring for the general (non-box) entry
point, and the note there on why the function returns a **new** geometry
handle that you must use in place of the one you passed in. For a
microstructure unit cell (e.g. a box with inclusions/pores boolean-subtracted
from it), use [`faces_on_plane`](@ref) to inspect face indices directly if
[`identify_periodic_box!`](@ref) can't find a single unambiguous face per
side (a boolean cut can split one outer face into several fragments).

## Alternative backend: Gmsh

Delone.jl's default backend is Netgen (`Delone.Netgen`), but it can
optionally use [Gmsh](https://gmsh.info/) as a second meshing backend for
STEP/IGES/BREP files. Unlike Netgen, Gmsh needs no hand-written binding
layer — `gmsh_jll` ships a complete, official Julia API, safely wrapped by
the registered `Gmsh` Julia package — so this is a lightweight, optional
[package extension](@ref "Package extensions"): loading `Gmsh` alongside
`Delone` activates `generate_gmsh_mesh`.

<!-- not converted to @example: Gmsh is a large optional dependency (Cairo,
     FLTK, X11, its own OCCT, ...) not installed in the docs build
     environment by design — this mirrors export.md's package-extension
     documentation style. -->
```julia
using Delone, Gmsh

s = generate_gmsh_mesh("model.step"; maxh=0.5)   # -> MeshLevelSnapshot{3,Float64,Int32}
size(s.coordinates, 2), size(s.volume_connectivity, 2)
```

`generate_gmsh_mesh` takes a file path (not an in-memory geometry object —
Gmsh's own API is file-based) and returns a [`MeshLevelSnapshot`](@ref)
directly, so it composes with everything that already accepts one:
`export_vtk`/`export_vtu`, `GeometryBasics.Mesh`, Makie plotting. v1 supports
a pure-tetrahedral 3D volume mesh only (Gmsh's default for a plain CAD
import); region/boundary names and 2D meshing are not yet wired up. See
[`generate_gmsh_mesh`](@ref)'s docstring for the full contract, including
why it throws `ArgumentError` rather than a raw Gmsh error on bad input.

## Choosing a workflow

| Goal | Suggested path |
|------|----------------|
| Existing CAD part | `load_step` / `load_brep` |
| Parametric 2D domain | `Circle` / `Rectangle` CSG |
| Custom 3D solid | OpenCascade.jl → `occ_geometry_from_brep_string` |
| Surface scan | `load_stl` |

Next: [Meshing](@ref "Meshing") turns any of these geometries into a simplicial mesh.
