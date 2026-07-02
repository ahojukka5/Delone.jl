# Local mesh sizing

Julian front door over Netgen's local-h machinery, plus the mechanism this
package actually uses to produce elements that are finer near a point.

!!! note "Read this before using `local_size`"
    In this build, Netgen's `RestrictLocalH`/`SetLocalH`/`LoadLocalMeshSize`
    do **not** influence [`generate_mesh`](@ref) — `GenerateMesh` recomputes
    its own local-h field during surface meshing and discards any restriction
    applied beforehand. `MeshOptions.local_size` and [`refine_near!`](@ref)
    therefore work by coarse generation followed by geometric mark-and-refine
    near the requested points — verified to genuinely localize in **both 2D
    and 3D**: 3D uses `mark_for_refinement!`/`bisect!`; 2D uses
    `mark_for_ngx_refinement!`/`ngx_refine!` instead, since plain `bisect!`
    refines 2D meshes uniformly regardless of marking. See
    [`refine_near!`](@ref)'s docstring for the full empirical writeup.

## Standalone size field

A spatial mesh-size field independent of any mesh — useful for building or
inspecting a target sizing before a mesh exists.

```@docs
LocalSizeField
local_size_field
field_h
field_min_h
```

## Mesh-level h-field operations

```@docs
restrict_h!
restrict_h_at!
mesh_h_at
set_global_h!
set_minimal_h!
```

## The mechanism that actually works: mark + bisect near a point

```@docs
refine_near!
local_size_requests
```
