# --- Gmsh backend stub (real implementation in ext/DeloneGmshExt.jl) --------
# Gmsh needs no hand-written CxxWrap binding layer the way Netgen does:
# `gmsh_jll` ships a complete, official, auto-generated Julia API
# (`gmsh_jll.gmsh_api`), wrapped safely by the registered `Gmsh` package
# (`include(gmsh_jll.gmsh_api)` + idempotent `initialize`/`finalize`). This
# stub exists only because Julia package extensions can add *methods* to an
# existing function binding, not introduce a new top-level name from scratch
# (same reason `export_vtu` has a stub in `src/export_mesh.jl`).

"""
    GmshPeriodicGroup

One registered periodic face pairing from a Gmsh-backend
[`generate_gmsh_mesh`](@ref) call (only populated under `result=true`), held
inside a [`GmshMeshGenerationResult`](@ref). The Gmsh-backend analogue of
what [`periodic_vertex_pairs`](@ref) reads off a live Netgen mesh.

# Fields
- `name::Union{Nothing,String}`
- `master_tags::Vector{Int}` — the "lo"/source face tags (`translation`
  maps a point on these faces to the corresponding point on `slave_tags`)
- `slave_tags::Vector{Int}` — the "hi"/copy face tags
- `translation::NTuple{3,Float64}`
- `vertex_pairs::Vector{Tuple{Int32,Int32}}` — `(master_idx, slave_idx)`
  pairs, 1-based into the accompanying `GmshMeshGenerationResult.snapshot`'s
  `coordinates` — same convention as [`periodic_vertex_pairs`](@ref)'s
  `(lo_idx, hi_idx)`, so `coordinates[:, slave_idx] - coordinates[:, master_idx]
  == translation` for every pair
"""
struct GmshPeriodicGroup
    name::Union{Nothing,String}
    master_tags::Vector{Int}
    slave_tags::Vector{Int}
    translation::NTuple{3,Float64}
    vertex_pairs::Vector{Tuple{Int32,Int32}}
end

"""
    GmshMeshGenerationResult

Returned by [`generate_gmsh_mesh`](@ref)/[`gmsh_mesh_from_brep_string`](@ref)
under `result=true`: the mesh `snapshot` (a `MeshLevelSnapshot{3,Float64,Int32}`)
plus any [`GmshPeriodicGroup`](@ref)s registered via `periodic=`/`periodic_box=`.
With `result=false` (the default), `generate_gmsh_mesh` returns the bare
`snapshot` directly instead — this type only exists to carry periodic
correspondence alongside it, mirroring how [`MeshGenerationResult`](@ref)
carries diagnostics alongside the Netgen-backend mesh handle.
"""
struct GmshMeshGenerationResult
    snapshot::Any
    periodic_groups::Vector{GmshPeriodicGroup}
end

"""
    generate_gmsh_mesh(path; maxh=nothing, regions=Dict(), boundary_names=Dict(),
                        refine_near=[], periodic=[], periodic_box=nothing,
                        result=false) -> MeshLevelSnapshot{3,Float64,Int32} | GmshMeshGenerationResult

Mesh a STEP/IGES/BREP file via Gmsh's OpenCASCADE-based CAD kernel and volume
mesher. Defined by the `DeloneGmshExt` package extension and only becomes
usable once `Gmsh` is loaded (`using Gmsh`) — see [`generate_mesh`](@ref) for
the always-available Netgen backend.

`regions`/`boundary_names` name solids/faces before meshing (via Gmsh
physical groups), populating the returned snapshot's `cell_regions`/
`boundary_regions`/`material_names`/`boundary_names` fields — otherwise left
at their pre-tagging placeholder values (`cell_regions` all `1`,
`boundary_regions` all `0`, both name dicts empty). Each dict maps a name to
one Gmsh entity tag or a vector of tags (dim=3 for `regions`, dim=2 for
`boundary_names`; see [`gmsh_geometry_info`](@ref)/[`faces_on_plane`](@ref)
to find tags without knowing Gmsh's numbering). Throws `ArgumentError` for
an unknown tag or a tag claimed by two different names — each entity may
belong to only one named region.

`refine_near` declares local mesh-size zones (Gmsh `Distance`+`Threshold`
size fields, combined via a `Min` field when more than one zone is given):
each entry is a named tuple with exactly one of `faces=`/`curves=`/`point=`
(tags from [`gmsh_geometry_info`](@ref), or an `(x,y,z)` point) plus
`hmin=`/`hmax=`/`distmin=`/`distmax=` (element size ramps linearly from
`hmin` at distance `<= distmin` to `hmax` at distance `>= distmax`). `maxh`
still applies as a hard cap on top of any `refine_near` field. Throws
`ArgumentError` for a malformed entry, an out-of-range parameter, or a
face/curve tag not found in this geometry.

`periodic`/`periodic_box` register pre-mesh periodic face identifications
(Gmsh's `gmsh.model.mesh.setPeriodic`), the Gmsh-backend analogue of
[`identify_periodic!`](@ref)/[`identify_periodic_box!`](@ref) — Gmsh copies
each `lo` face's surface mesh through `translation` to build the matching
`hi` face's mesh, guaranteeing exact node correspondence. `periodic` entries
are named tuples `(lo=, hi=, translation=, name=nothing)` (`lo`/`hi` are
dim=2 face tags, one or several). **Important difference from the Netgen
backend**: Gmsh's `setPeriodic` pairs `lo`/`hi` element-wise by *position*
(`lo[i]` with `hi[i]`) — it does **not** do Netgen's `netgen::Identify`-style
N×M geometric fragment matching, so multi-face `lo`/`hi` vectors must
already be given in corresponding order. `periodic_box` is the axis-aligned
convenience (`:x`, `:y`, `:z`, or a vector of axes) that finds each axis's
extreme faces automatically, mirroring `identify_periodic_box!`, but — for
the reason above — only when exactly one face is found at each extreme;
throws `ArgumentError` on a fragmented periodic face (a boolean-cut
microstructure feature touching the boundary), where `identify_periodic_box!`
on the Netgen backend now succeeds. Use explicit `periodic=` entries with
manually-ordered fragment lists as the fallback in that case. The periodic
constraint is applied to the mesh regardless of `result`; `result=true`/
[`GmshMeshGenerationResult`](@ref) is only needed to additionally read back
the registered [`GmshPeriodicGroup`](@ref)s and their `vertex_pairs` — with
`result=false` (the default) you still get a periodic mesh, just no
correspondence readback. Throws
`ArgumentError` for a malformed entry or a face tag not found in this
geometry.
"""
function generate_gmsh_mesh(args...; kwargs...)
    throw(ArgumentError(
        "generate_gmsh_mesh requires Gmsh to be loaded (`using Gmsh`) to activate " *
        "the DeloneGmshExt package extension; see generate_mesh for the " *
        "always-available Netgen backend"))
end

"""
    gmsh_mesh_from_brep_string(brep::AbstractString; kwargs...) -> MeshLevelSnapshot{3,Float64,Int32}

Mesh an in-memory BREP string (e.g. from `Monge.to_brep_string`) via Gmsh —
the Gmsh-backend analogue of [`occ_geometry_from_brep_string`](@ref)'s
BREP-string bridge for Netgen. `kwargs...` are forwarded to
[`generate_gmsh_mesh`](@ref) verbatim (`maxh`, `regions`, `boundary_names`, ...).

Gmsh's own API has no in-memory-string import (unlike Netgen's), so this
writes `brep` to a temporary `.brep` file internally and delegates to
[`generate_gmsh_mesh`](@ref) — equivalent to, but safer than, passing a raw
in-memory shape pointer across two independently-built OCCT libraries.
Defined by the `DeloneGmshExt` package extension and only becomes usable
once `Gmsh` is loaded (`using Gmsh`).
"""
function gmsh_mesh_from_brep_string(args...; kwargs...)
    throw(ArgumentError(
        "gmsh_mesh_from_brep_string requires Gmsh to be loaded (`using Gmsh`) to " *
        "activate the DeloneGmshExt package extension; see " *
        "occ_geometry_from_brep_string for the always-available Netgen backend"))
end

"""
    gmsh_geometry_info(path::AbstractString) -> NamedTuple

Import a STEP/IGES/BREP file into a throwaway Gmsh model and report its OCC
face/solid tags and bounding boxes, without meshing — the Gmsh-backend
analogue of [`occ_nr_faces`](@ref)/[`occ_face_bbox`](@ref) for identifying
periodic faces ([`generate_gmsh_mesh`](@ref)'s `periodic=`) or region solids
(`regions=`/`boundary_names=`) before meshing.

Returns `(faces=..., solids=..., bounding_box=...)`: `faces`/`solids` are
`Vector`s of `(tag, xmin, ymin, zmin, xmax, ymax, zmax)` named tuples (one
per OCC face/solid); `bounding_box` is the same shape for the whole model.
Use [`faces_on_plane`](@ref)'s `faces` method to find faces on an
axis-aligned plane (e.g. the extremes of an RVE unit cell) without knowing
Gmsh's tag numbering.

Defined by the `DeloneGmshExt` package extension and only becomes usable
once `Gmsh` is loaded (`using Gmsh`).
"""
function gmsh_geometry_info(args...; kwargs...)
    throw(ArgumentError(
        "gmsh_geometry_info requires Gmsh to be loaded (`using Gmsh`) to " *
        "activate the DeloneGmshExt package extension"))
end

"""
    faces_on_plane(faces::AbstractVector{<:NamedTuple}, axis, value; atol=1e-6) -> Vector{Int}

Gmsh-tag analogue of [`faces_on_plane`](@ref)'s OCC-geometry method: given
the `faces` list from [`gmsh_geometry_info`](@ref), return the Gmsh face
*tags* (not positions — Gmsh tags aren't guaranteed contiguous) whose
bounding box is flat against the plane `axis = value`. Same semantics,
defaults, and error messages as the OCC-geometry method; does not require
`Gmsh` to be loaded (operates on the plain named tuples `gmsh_geometry_info`
already extracted).
"""
function faces_on_plane(faces::AbstractVector{<:NamedTuple}, axis::Symbol, value::Real;
                         atol::Real=1e-6)
    haskey(_AXIS_INDEX, axis) || throw(ArgumentError(
        "faces_on_plane: axis must be :x, :y, or :z (got $axis)"))
    atol > 0 || throw(ArgumentError("faces_on_plane: atol must be > 0 (got $atol)"))
    k = _AXIS_INDEX[axis]
    result = Int[]
    for f in faces
        lo = (f.xmin, f.ymin, f.zmin)[k]
        hi = (f.xmax, f.ymax, f.zmax)[k]
        if abs(lo - value) <= atol && abs(hi - value) <= atol
            push!(result, f.tag)
        end
    end
    return result
end
