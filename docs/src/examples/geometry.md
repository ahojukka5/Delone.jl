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

## Choosing a workflow

| Goal | Suggested path |
|------|----------------|
| Existing CAD part | `load_step` / `load_brep` |
| Parametric 2D domain | `Circle` / `Rectangle` CSG |
| Custom 3D solid | OpenCascade.jl → `occ_geometry_from_brep_string` |
| Surface scan | `load_stl` |

Next: [Meshing](@ref "Meshing") turns any of these geometries into a simplicial mesh.
