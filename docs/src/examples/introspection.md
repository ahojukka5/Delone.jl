# Structured reports & introspection

Alongside the mesh/geometry API, Delone.jl exposes a **read-only reporting
layer**: structured, serializable results for validation, quality, meshability,
and readiness checks. It exists so a calling tool, solver driver, or LLM agent
can inspect *what happened* and *what to do next* without touching raw
`Delone.Internals` handles. The generic entry points (`report`, `validate`,
`readiness`, `to_namedtuple`) are owned by **OodiCore**, a small shared
contract package — Delone.jl only adds methods and concrete report types.
`test/llm_feedback.jl` exercises this whole layer end to end and is the most
current reference if this page and the code ever drift.

The examples on this page share the `cylinder.brep` fixture (unit cylinder,
radius 1, height 2) and one running `Delone` session.

## MeshOptions: construction and validation

```@example introspection
using Delone

opts = MeshOptions(maxh=0.5, minh=0.05, grading=0.3)
validate_options!(opts)          # throws ArgumentError on bad combinations, returns opts

# The bare `MeshOptions(...)` constructor does *not* validate — only
# `validate_options!`/`mesh_options` do. Wrap the throwing calls below.
try
    validate_options!(MeshOptions(maxh=-1.0))           # ArgumentError: maxh must be > 0
catch e
    println("caught: ", e)
end
try
    validate_options!(MeshOptions(maxh=1.0, minh=2.0))  # ArgumentError: minh must be ≤ maxh
catch e
    println("caught: ", e)
end
```

`validate(opts)` is the non-throwing counterpart, returning an OodiCore
`ValidationReport`:

```jldoctest
using Delone

vr = validate(MeshOptions(maxh=1.0, minh=2.0))
(isvalid(vr), any(d -> d.severity == :error, vr.diagnostics))

# output

(false, true)
```

## Structured mesh generation

`generate_mesh` normally returns a bare mesh and throws on failure. Pass
`result=true` for a [`MeshGenerationResult`](@ref) instead — meshing failures
become data, not exceptions:

```@example introspection
cylinder_path = joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "cylinder.brep")
geom = load_brep(cylinder_path)

result = generate_mesh(geom; options=opts, result=true)
println("success: ", result.success)           # Bool
println("has mesh: ", result.mesh !== nothing)  # mesh handle, or `nothing` on failure
println("options: ", result.options)            # the MeshOptions actually used
println("elapsed_seconds >= 0: ", result.elapsed_seconds >= 0)
println("diagnostics: ", result.diagnostics)    # MeshGenerationDiagnostics: failure_stage, messages, suggestions

m = mesh(result)              # extract the mesh; throws if result.success == false
Int(num_cells(m))
```

A failed attempt (e.g. `nothing` geometry, an empty mesh, or a backend
`MESHING3_*` failure code) sets `diagnostics.failure_stage` (one of
`:geometry_import`, `:surface_mesh`, `:volume_mesh`, `:optimization`,
`:post_validation`, `:unknown`) and fills `diagnostics.suggestions` with
actionable `DiagnosticMessage`s (e.g. "try increasing maxh" or "heal/repair CAD
geometry"). Use [`generate_mesh_result`](@ref) directly for the same
non-throwing path (`try_generate_mesh` is a deprecated alias).

## Mesh reports: validation, quality, tags

```@example introspection
r = mesh_report(m)        # MeshReport: validation + quality + topology + tags
println("valid: ", r.validation.valid)
println("node_count: ", r.validation.node_count)
println("element_count: ", r.validation.element_count)
println("isvalid(m): ", isvalid(m))                 # shortcut: r.validation.valid

q = quality(m)             # MeshQualityReport (mesh_quality is a deprecated alias)
println("min_quality in [0,1]: ", 0 <= q.min_quality <= 1)
println("mean_quality in [0,1]: ", 0 <= q.mean_quality <= 1)
println("min_edge_length <= max_edge_length: ", q.min_edge_length <= q.max_edge_length)

tr = tag_report(m)         # MeshTagReport: boundary/region tag inventory
tr
```

All report types have readable `show` methods (`string(r)`), and none of them
expose `Delone.Internals` handles — `r.validation isa Delone.Internals.Mesh`
is always `false`.

## Meshability: checking before you commit

`meshability_report` is a pre-meshing sanity check (options + geometry
presence, sizing hints) — it doesn't guarantee success but flags obvious
blockers:

```@example introspection
mr = meshability_report(geom; options=opts)
println("likely_meshable: ", mr.likely_meshable)   # Bool or nothing
mr.suggestions                                     # Vector{DiagnosticMessage}
```

`meshing_diagnostics(geom, opts, result)` does the post-mortem version,
combining a `MeshGenerationResult` with option context; `suggest_mesh_fixes`
pulls actionable fixes out of a result (optionally cross-referenced against a
`MeshReport` for quality-driven suggestions like inverted elements or
untagged boundaries).

## Hierarchy & session reports

```@example introspection
h = mesh_hierarchy(geom; maxh=0.5, levels=1)
rr = refine!(h; mode=:uniform, result=true)   # RefinementResult when result=true
println("refinement success: ", rr.success)

hr = hierarchy_report(h)                 # MeshHierarchyReport
println("nlevels: ", hr.nlevels)
println("level 1 element_count: ", hr.levels[1].element_count)
println("level 2 element_count: ", hr.levels[2].element_count)
println("transfer[1].inherited_node_count: ", hr.transfers[1].inherited_node_count)
```

The same pattern works on a live `MeshHierarchySession` via
`hierarchy_report(session)` and `refine_session!(session; mode=:uniform,
result=true)`. A [`RefinementResult`](@ref) reports `success`,
`old_level_count` → `new_level_count`, and `old_element_count` →
`new_element_count`, so a caller can tell *whether refinement actually grew
the mesh* without re-deriving it from before/after handles.

## The `report` / `validate` / `readiness` contract

Three generic entry points, dispatched by argument type, cover "what is this?",
"is this internally consistent?", and "is this ready for the next stage?":

| Call | Returns |
|------|---------|
| `report(mesh)` | [`MeshReport`](@ref) (same as `mesh_report(mesh)`) |
| `report(hierarchy_or_session)` | [`MeshHierarchyReport`](@ref) |
| `report(generation_or_refinement_result)` | the result itself (idempotent) |
| `validate(mesh)` | `MeshValidationReport` |
| `validate(::MeshOptions)` | OodiCore `ValidationReport` |
| `readiness(geom, MeshingTarget(options=...))` | [`MeshabilityReport`](@ref) |
| `readiness(mesh_or_hierarchy, OodiImportTarget())` | [`OodiSnapshotReadiness`](@ref) |
| `readiness(hierarchy_or_session, GeometricMultigridTarget())` | OodiCore `ReadinessReport` |

```@example introspection
try
    readiness(geom, MeshingTarget())                       # ArgumentError: needs options=
catch e
    println("caught: ", e)
end
println("likely_meshable: ", readiness(geom, MeshingTarget(options=opts)).likely_meshable)

gmg = readiness(h, GeometricMultigridTarget())
println("subject: ", gmg.subject)       # :geometric_multigrid
println("isready(gmg): ", isready(gmg))       # needs ≥2 levels + valid coarse→fine transfers
```

`oodi_snapshot_readiness(x)` (the concrete function behind `OodiImportTarget`)
reports `dimension`, `hierarchy_levels`, and `parent_node_transfers` — the
minimum a downstream Oodi-ecosystem consumer needs before importing a
snapshot.

## Serialization: `to_namedtuple`

Every report type above converts recursively to a plain `NamedTuple` — numbers,
strings, symbols, vectors, dicts, nested named tuples — safe for JSON logging
or an LLM tool response. Raw mesh handles are never emitted; a
`MeshGenerationResult` is summarized (`has_mesh`, `node_count`, `cell_count`)
instead of embedding `r.mesh`:

```@example introspection
nt = to_namedtuple(mesh_report(m))
println("nt.validation.valid: ", nt.validation.valid)
println("nt.quality.min_quality in [0,1]: ", 0 <= nt.quality.min_quality <= 1)

ntr = to_namedtuple(generate_mesh(geom; maxh=0.5, result=true))
println("success: ", ntr.success, ", has_mesh: ", ntr.has_mesh, ", node_count > 0: ", ntr.node_count > 0)
haskey(ntr, :mesh)   # false — raw handle never serialized
```

## Export & preview formats

Lightweight, dependency-free export for human or LLM feedback loops (no full
viewer):

```@example introspection
vtk_path = tempname() * ".vtk"
obj_path = tempname() * ".obj"
svg_path = tempname() * ".svg"

export_vtk(m, vtk_path)           # ASCII VTK unstructured grid (volume + boundary)
export_obj(m, obj_path)           # Wavefront OBJ (boundary/domain triangles)

m2d = generate_mesh(geometry2d(Circle(0.0, 0.0, 1.0, "disk", "boundary")); maxh=0.4)
export_svg_2d(m2d, svg_path)      # 2D-only SVG preview

preview_path = tempname() * ".vtk"
export_mesh_preview(m, preview_path; format=:vtk)  # dispatches to :vtk or :obj

p1 = mesh_preview(m; format=:vtk)                    # writes to a fresh tempfile, returns its path
ps = mesh_previews(m; formats=[:vtk, :obj])          # one tempfile per format

(isfile(vtk_path), isfile(obj_path), isfile(svg_path), isfile(p1), all(isfile, ps))
```

For real binary/compressed VTU with cell data, Makie plotting, or
GeometryBasics interop, see the [package extensions](../reference/export.md#Package-extensions)
(`DeloneWriteVTKExt`, `DeloneMakieExt`, `DeloneGeometryBasicsExt`) — each
activates once the corresponding optional dependency is loaded.

Next: [Tags, hp-adaptivity & FEM data](@ref "Tags, hp-adaptivity & FEM data").
