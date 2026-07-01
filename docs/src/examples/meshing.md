# Meshing

## Basic mesh generation

Every mesh starts from a geometry object and a characteristic mesh size `maxh`
(smaller → finer mesh):

```julia
using Netgen

disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
mesh = generate_mesh(geometry2d(disk); maxh=0.4)
```

3D example from a STEP file:

```julia
geom = load_step("frame.step")
mesh = generate_mesh(geom; maxh=0.5)
```

`generate_mesh` composes the 1:1 Netgen calls: `new_mesh`, `SetGeometry`,
`MeshingParameters`, `GenerateMesh`.

## Reading mesh data

Julian helpers loop over 1-based Netgen indices:

```julia
X = points(mesh)                  # 3×np (z=0 for 2D meshes)

# 3D volume mesh
T = tetrahedra(mesh)              # 4×ne, 1-based node indices
F = surface_triangles(mesh)       # 3×nse boundary triangles

# 2D domain mesh
Tr = triangles2d(mesh)            # domain triangles
S  = segments2d(mesh)             # boundary segments
```

Raw accessors remain available: `GetNP`, `GetNE`, `Point(mesh, i)`,
`VolumeElement(mesh, i)`, etc.

## Mesh parameters

For finer control, build `MeshingParameters` directly:

```julia
mp = MeshingParameters()
maxh!(mp, 0.2)
minh!(mp, 0.01)          # optional lower bound
grading!(mp, 0.3)        # mesh grading between coarse and fine regions

m = new_mesh()
SetGeometry(m, geom)
GenerateMesh(geom, m, mp)
```

Set `secondorder!(mp, true)` before generation if you want second-order elements
from the mesher (alternative: `make_second_order!` after the fact — see [Refinement](@ref "Refinement")).

## Topology

After mesh changes, refresh topology tables:

```julia
Netgen.UpdateTopology(mesh)
topo = Netgen.GetTopology(mesh)
Netgen.GetNEdges(topo)
Netgen.GetNFaces(topo)
```

Enable optional parent-edge tables before refinement (see
[Tags, hp-adaptivity & FEM data](@ref "Tags, hp-adaptivity & FEM data")):

```julia
enable_topology_table!(mesh, "parentedges")
enable_topology_table!(mesh, "parentfaces")
```

## Copying meshes

`copy_mesh` (C++ `Mesh.assign`) duplicates a mesh so you can refine one level
without destroying another:

```julia
coarse = generate_mesh(geom; maxh=0.5)
fine   = copy_mesh(coarse)
refine!(fine)
```

This pattern underlies multigrid hierarchies — see
[Mesh hierarchies & sessions](@ref "Mesh hierarchies & sessions").

## STL surfaces

```julia
stl = load_stl("scan.stl")
mesh = generate_mesh(stl; maxh=1.0)   # surface triangle mesh
```

STL geometry is triangle-based; volume meshing typically starts from a closed
BREP/STEP solid instead.

Next: [Refinement](@ref "Refinement").
