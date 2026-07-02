# Mesh hierarchies & sessions

There are two complementary ways to work with multiple mesh levels:

1. **Low-level `Ngx_Mesh` maps** on a single refined mesh (`parent_nodes`, …).
2. **Live `MeshHierarchySession`** with explicit levels and optional **snapshots**.

The examples below share one geometry — the `cylinder.brep` fixture (unit
cylinder, radius 1, height 2) — across the whole page.

## `Ngx_Mesh` on one mesh

After refining in place, parent data describes the immediate coarse→fine
relation on that mesh object:

```@example hierarchy
using Delone

cylinder_path = joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "cylinder.brep")
geom = load_brep(cylinder_path)
mesh = generate_mesh(geom; maxh=0.5)
refine!(mesh)

P  = parent_nodes(mesh)           # 2×np vertex parents
PE = parent_elements(mesh)        # volume element parents
(size(P), length(PE))
```

`num_levels`, `level_nvertices`, and `prolongation` help when Netgen stores
multiple embedded levels on one `Mesh`.

## Building a two-level hierarchy manually

```@example hierarchy
coarse = generate_mesh(geom; maxh=0.5)
fine   = copy_mesh(coarse)
refine!(fine)

# coarse is unchanged; fine carries parent maps back to coarse
h = MeshHierarchy(geom, Any[coarse, fine])   # 2-arg constructor: (geometry, meshes)
nlevels(h)
```

`uniform_hierarchy(geom; levels=3, maxh=0.5)` repeats copy + refine.

## Live session API

A **session** owns geometry and one mesh handle per level. Refinement **requests**
mutate the session and bump a `generation` counter:

```@example hierarchy
s = mesh_session(geom; maxh=0.5)

println("nlevels: ", nlevels(s))          # 1
m1 = finest(s)      # same as level_mesh(s, 1)

request_uniform_refinement!(s)
println("nlevels after refine: ", nlevels(s))          # 2
m2 = finest(s)      # refined level

generation(s)       # incremented — snapshots may be stale
```

Other requests:

```@example hierarchy
marked = falses(num_cells(finest(s)))
marked[1:length(marked) ÷ 4] .= true

request_marked_refinement!(s, marked)   # adaptive, appends level
request_second_order!(s)                # in-place on finest level only
nlevels(s)
```

`level_mesh(s, k)` returns the **live** handle for level `k`. For an in-place
mutation that isn't one of the `request_*!` refinements, use
`mutate_level_mesh!` to keep `generation` tracking correct instead of mutating
`level_mesh(s, k)` directly:

<!-- not converted to @example: illustrates the mutate_level_mesh! pattern with
     a placeholder do-block body ("in-place mesh mutation via Delone.Internals
     if needed") rather than a concrete mutation — there is no single concrete
     Internals call that is representative here, and building one up just for
     a doctest is more trouble than the pattern is worth to pin. -->
```julia
mutate_level_mesh!(s, 2) do m       # bump_generation=true by default
    # in-place mesh mutation via Delone.Internals if needed
end                                  # -> returns the session; generation bumped
```

## Snapshots for downstream consumers

Solvers that need **immutable** mesh data copy snapshots instead of holding live
handles:

```@example hierarchy
snap = level_snapshot(s, 1)                     # MeshLevelSnapshot (coordinates, connectivity, …)

# supported_snapshot_topology takes a *mesh handle*, not a snapshot object
supported_snapshot_topology(level_mesh(s, 1))   # true — pure Tet4/Tri3 simplex mesh

hier = hierarchy_snapshot(s)

# transfer_snapshot is defined for levels k ≥ 2 (level 1 has no coarser parent)
transfer = transfer_snapshot(s, 2)              # coarse → fine prolongation data
(snap.element_type, transfer.level_from, transfer.level_to)
```

Snapshots record `generation` at capture time. After `request_second_order!` or
in-place hp changes, re-snapshot if `snapshot.generation != generation(s)`.

### Supported snapshot topologies

| Mesh | `volume_connectivity` | Notes |
|------|----------------------|-------|
| 3D Tet4 | yes | corners only after second-order curving |
| 3D Tri3 boundary | via surface extraction | |
| 2D Tri3 | yes | domain triangles |
| 2D Segment | boundary segments | |

Transfer weights use documented semantics (`transfer_weight_semantics` →
`:topological_bisection_default`).

## Integration contract (summary)

```
Delone.jl provides   live handles, refinement requests, parent maps,
                     region/tag data, copied snapshots, partition hints
Consumer provides    FE spaces, DOFs, operators, estimators, partition policy
```

Delone.jl does **not** assemble prolongation/restriction matrices or run linear
solvers.

Next: [Structured reports & introspection](@ref "Structured reports & introspection").
