# Tutorial: from geometry to a simulation-ready mesh hierarchy

This page is a step-by-step walkthrough for a brand-new user: install the
package, build a first 2D and 3D mesh, read structured diagnostics, refine
geometry-aware, and grow a mesh hierarchy. Each step is a runnable
`@example` block that builds on the previous one. If you only want a quick
reference table of what exists, see [Home](index.md) or
[Wrapped capabilities](capabilities.md); this page is the guided tour.

## 1. Install and build

Delone.jl wraps a native library (`libnetgen_cxxwrap`) that is not registered
yet, so it must be built locally before first use. See
[Development](development.md) for the exact commands
(`gen/build_local.jl`, then `pkg> test Delone` or `julia --project=docs
docs/make.jl` for these docs). The rest of this tutorial assumes the package
is already built and `using Delone` works.

## 2. A first 2D mesh

The simplest possible geometry is a disk built with 2D CSG. `Circle` takes a
center, radius, a material name, and a boundary name; `geometry2d` turns it
into a meshable geometry object; `generate_mesh` produces a mesh at a target
characteristic size `maxh`:

```@example tutorial
using Delone

disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
geom = geometry2d(disk)
disk_mesh = generate_mesh(geom; maxh=0.4)

num_nodes(disk_mesh), num_cells(disk_mesh)
```

`points(disk_mesh)` gives coordinates, `triangles2d(disk_mesh)`/`segments2d(disk_mesh)`
give domain/boundary connectivity — see [Meshing](@ref "Meshing") for the full
extraction API.

## 3. A first 3D mesh from a STEP file

3D geometry usually comes from CAD. `load_step` reads a STEP file into a
Netgen geometry object; the rest of the workflow is identical to the 2D case.
This tutorial uses the repository's own test fixture so the example is
reproducible without any external file:

```@example tutorial
step_file = joinpath(dirname(dirname(pathof(Delone))), "test", "fixtures", "frame.step")

geom3d = load_step(step_file)
mesh3d = generate_mesh(geom3d; maxh=40.0)

num_nodes(mesh3d), num_cells(mesh3d)
```

(In your own project, replace `step_file` with a plain path such as
`"model.step"`.) `tetrahedra(mesh3d)` and `surface_triangles(mesh3d)` give the
volume and boundary connectivity — see [Building geometry](examples/geometry.md)
for STEP/IGES/BREP/STL import and programmatic OCC modeling via
OpenCascade.jl.

## 4. `MeshOptions` and structured diagnostics

Keyword arguments like `maxh=...` are convenient, but real pipelines want
validated, inspectable options and a result they can branch on instead of a
thrown exception. [`MeshOptions`](@ref) bundles the generation parameters;
`generate_mesh(...; result=true)` returns a [`MeshGenerationResult`](@ref)
instead of throwing on failure:

```@example tutorial
opts = MeshOptions(maxh=0.4, minh=0.05, grading=0.3)

result = generate_mesh(geom; options=opts, result=true)
result.success
```

```@example tutorial
if result.success
    m = generated_mesh(result)      # extract the mesh; throws if success == false
    r = mesh_report(m)              # MeshReport: validation + quality + topology + tags
    r.validation.valid, r.quality.min_quality
else
    result.diagnostics              # failure_stage, messages, suggestions
end
```

See [MeshOptions](mesh_options.md) for every field, its default, and its
validation rule, and [Structured reports & introspection](examples/introspection.md)
for the full reporting layer (`meshability_report`, `quality`, `tag_report`, …).

## 5. Refinement: geometry-aware boundary snapping

`refine!` performs uniform, geometry-aware h-refinement in place: new
boundary nodes are **projected onto the true curved boundary**, not just
averaged from their parents. `copy_mesh` keeps the original mesh intact as
its own level:

```@example tutorial
coarse = generate_mesh(geom; maxh=0.5)
fine = copy_mesh(coarse)
refine!(fine)

num_nodes(coarse), num_nodes(fine)
```

`parent_nodes(fine)` records, for every node of the fine mesh, the two
coarse-mesh nodes it descends from (`(0, 0)` for a node the fine mesh
inherited unchanged from the coarse mesh, keeping the **same index**):

```@example tutorial
P = parent_nodes(fine)
Xc, Xf = points(coarse), points(fine)

# find one newly created boundary node and look at its parents
j = findfirst(k -> P[1, k] != 0, axes(P, 2))
a, b = P[1, j], P[2, j]

chord_midpoint = (Xc[:, a] .+ Xc[:, b]) ./ 2
actual_node = Xf[:, j]

hypot(chord_midpoint[1], chord_midpoint[2]), hypot(actual_node[1], actual_node[2])
```

The chord midpoint of two parents on the unit circle sits slightly *inside*
the disk (radius `< 1`); the actual new node is snapped back onto the circle
at radius `1`. That is what "geometry-aware" refinement means in practice,
and it is why `parent_nodes` — not the raw coordinate average — is the
correct way for a consumer to build interpolation/prolongation operators.

## 6. Building a `MeshHierarchy` and reading `hierarchy_report`

For more than two levels, or when you want a single object that tracks the
whole stack, use [`MeshHierarchy`](@ref):

```@example tutorial
h = mesh_hierarchy(geom; maxh=0.5, levels=1)
refine!(h; mode=:uniform)
refine!(h; mode=:uniform)

nlevels(h)
```

`hierarchy_report` gives a structured, per-level and per-transfer summary —
node/element counts, validity, and whether refinement actually grew the mesh
at each step:

```@example tutorial
hr = hierarchy_report(h)
hr.nlevels, hr.valid
```

```@example tutorial
hr.levels[end].element_count > hr.levels[1].element_count
```

`readiness(h, GeometricMultigridTarget())` answers the pipeline-facing
question directly — "is this hierarchy usable for geometric multigrid?" —
without a consumer having to re-derive it from level reports:

```@example tutorial
gmg = readiness(h, GeometricMultigridTarget())
isready(gmg)
```

## 7. Next steps: live sessions, snapshots, and solver integration

Everything above uses a static `MeshHierarchy` built once. A real simulation
loop typically wants to *grow* the hierarchy adaptively while it runs, and to
hand a downstream solver **copied, immutable data** rather than live Netgen
handles. That is exactly what [`MeshHierarchySession`](@ref) and the
snapshot types (`level_snapshot`, `hierarchy_snapshot`, …) are for — see
[Sessions & snapshots](sessions_snapshots.md) for the full staleness/generation
contract, and [Mesh hierarchies & sessions](examples/hierarchy.md) for a
worked example with `request_*!` refinement requests.
