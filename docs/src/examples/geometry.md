# Building geometry

Netgen.jl accepts geometry from files, 2D constructive solid geometry (CSG), or
programmatic OpenCASCADE modeling.

## Import CAD files

```julia
using Netgen

geom = load_step("model.step")       # also load_iges, load_brep
geom = load_geometry("part.brep")    # extension dispatch

# STL → surface mesh pipeline (3D triangle soup)
stl_geom = load_stl("surface.stl")
```

`load_*` functions return a Netgen geometry object (`NetgenGeometry` /
`OCCGeometry` / `STLGeometry`) that you pass to `generate_mesh` (see [Meshing](@ref "Meshing")).

## 2D CSG — disks, rectangles, booleans

2D domains use `geom2d` / `csg2d`. Primitives carry a material label and a
boundary label:

```julia
using Netgen

# Unit disk (radius 1), curved boundary
disk = Circle(0.0, 0.0, 1.0, "disk", "outer")
geom = geometry2d(disk)

# Plate with a rectangular notch (difference)
outer = Circle(0.0, 0.0, 1.0, "plate", "circle")
notch = Rectangle(-0.2, -1.5, 0.2, 0.0, "notch", "rect")
geom = geometry2d(outer - notch)

# Union / intersection: use + and * ; difference: -
```

Boolean operators match Netgen's CSG conventions (`+` union, `*` intersection,
`-` difference).

## 3D modeling with OpenCASCADE (`Netgen.OCC`)

`Netgen.OCC` exposes raw OCCT class names — no Julian aliases. Build a
`TopoDS_Shape`, then wrap it:

```julia
using Netgen
using Netgen.OCC

# Cylinder: radius 1, height 2, axis along z
ax = gp_Ax2(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 0.0, 1.0))
cyl = Shape(BRepPrimAPI_MakeCylinder(ax, 1.0, 2.0))

# Box from two corners
box = Shape(BRepPrimAPI_MakeBox(gp_Pnt(0.0, 0.0, 0.0), gp_Pnt(1.0, 1.0, 1.0)))

# Sphere
sphere = Shape(BRepPrimAPI_MakeSphere(gp_Pnt(0.0, 0.0, 0.0), 1.0))

geom = OCCGeometry(cyl)   # meshable Netgen geometry
```

### Booleans

```julia
big   = Shape(BRepPrimAPI_MakeBox(gp_Pnt(0,0,0), gp_Pnt(2,2,2)))
small = Shape(BRepPrimAPI_MakeSphere(gp_Pnt(1,1,1), 0.6))
cut   = Shape(BRepAlgoAPI_Cut(big, small))
geom  = OCCGeometry(cut)
```

### Fillets and offsets

Fillet/chamfer and offset APIs (`BRepFilletAPI_*`, `BRepOffsetAPI_*`) are
wrapped 1:1. See the OCC tests under `test/occ_*.jl` for patterns.

### Export / re-import

```julia
BRepTools_Write(shape, "part.brep")
geom = load_brep("part.brep")
```

## Choosing a workflow

| Goal | Suggested path |
|------|----------------|
| Existing CAD part | `load_step` / `load_brep` |
| Parametric 2D domain | `Circle` / `Rectangle` CSG |
| Custom 3D solid | `Netgen.OCC` primitives + booleans |
| Surface scan | `load_stl` |

Next: [Meshing](@ref "Meshing") turns any of these geometries into a simplicial mesh.
