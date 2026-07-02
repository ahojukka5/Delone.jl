# --- local mesh-size control -------------------------------------------------
#
# Julian front door over Netgen's local-h machinery (`Internals.LocalH`,
# `Mesh::GetH/SetGlobalH/SetMinimalH`). See the module docstring below for
# what is and is not verified to influence `generate_mesh` in this build.
#
# VERIFIED (via standalone probing, see test/local_sizing.jl):
#   - `Internals.new_localh(pmin, pmax, globalh)` / `SetH` / `GetH` / `GetMinH`
#     on a standalone `LocalH` field: fully works, independent of any mesh.
#   - `Internals.GetH(mesh, point)`, `SetGlobalH(mesh, h)`, `SetMinimalH(mesh, h)`
#     on an existing mesh: fully works (already exercised in test/mesh2.jl).
#   - `Internals.RestrictLocalH(mesh, point, h)` and
#     `Internals.SetLocalH(mesh, localh)`: the call succeeds and immediately
#     updates `GetH(mesh, point)` to reflect the requested size — but this
#     package's `GenerateMesh(geometry, mesh, meshingparameters)` entry point
#     (the only OCC-geometry meshing path wrapped here) recomputes its own
#     local-h field internally during surface meshing and DISCARDS any
#     restriction applied beforehand. The identical behavior was confirmed for
#     `Internals.LoadLocalMeshSize` (a `.msz` file loader — internally calls
#     `RestrictLocalH`). None of these three actually make `generate_mesh`
#     produce smaller elements near a point in this build.
#   - `Internals.OptimizeVolume` (a post-generation quality pass) does read the
#     mesh's local-h field, but it only removes/flips elements to improve
#     quality — it cannot ADD elements to reach a finer local target, so it is
#     not a usable substitute for real local refinement either.
#
# NOT USABLE for pre-generation local sizing (documented, not silently
# dropped): `RestrictLocalH`, `RestrictLocalHLine`, `SetLocalH`,
# `LoadLocalMeshSize` as *inputs to `generate_mesh`*. They remain useful for
# introspecting/annotating an existing size field (hence still wrapped below
# for `LocalSizeField` and for post-hoc `mesh_h_at`/`set_global_h!`/
# `set_minimal_h!`), and for future work if a lower-level
# surface-mesh-then-volume-mesh entry point is ever wrapped.
#
# WORKING mechanism for "mesh finer near a point" end-to-end: generate a
# coarse mesh, then geometrically mark elements near the target point(s) and
# run the existing, already-proven `mark_for_refinement!` / `bisect!` pipeline
# (see refinement.jl). `MeshOptions.local_size` below is wired to exactly this
# path in `to_meshing_parameters`/a post-generation hook, not to
# `RestrictLocalH`.
#
# IMPORTANT 2D vs 3D asymmetry (verified empirically, see test/local_sizing.jl):
#   - In 3D, marking elements before `bisect!` has a real, measurable
#     localizing effect ON TOP OF `bisect!`'s otherwise mostly-uniform
#     refinement: an apples-to-apples comparison (identical base mesh, marked
#     vs. unmarked, same query location) showed meaningfully shorter edges and
#     several times more elements near the marked region.
#   - In 2D, the same apples-to-apples comparison showed ZERO difference
#     between marking a small subset of triangles and marking nothing at all
#     — `bisect!` on a 2D mesh refines fully uniformly regardless of
#     `mark_for_refinement!` in this build. `refine_near!`/`local_size` still
#     run without error in 2D (so callers aren't broken), but only achieve
#     uniform refinement there, not spatial localization — flagged via a
#     one-time `@warn`, not silently passed off as working.
#
#     POSSIBLE FIX PATH (found later, not yet integrated here): the
#     `mark_for_ngx_refinement!`/`ngx_refine!` pair (see hp.jl) was verified
#     in docs/src/examples/refinement.md to produce real localized refinement
#     on a 2D mesh, unlike `mark_for_refinement!`/`bisect!`. `refine_near!`
#     could likely be rewritten to use that pair for its 2D path instead of
#     warning — worth a follow-up rather than assuming 2D localization is a
#     fundamental limitation.

# --- standalone size field ---------------------------------------------------

"""
    LocalSizeField

A standalone spatial mesh-size field, independent of any mesh. Wraps
`Internals.new_localh` (a bounding box + a default/global size) plus any
number of point-wise overrides applied via `Internals.SetH`.

Useful for building a size specification before a mesh exists, or for
querying/visualizing a target sizing independent of the mesher.

# Fields
- `pmin`, `pmax`: the bounding box, `NTuple{3,Float64}`
- `global_h`: the default/background mesh size
- `refine_at`: the `(point, h)` overrides applied, in application order
- `handle`: the underlying `Internals.LocalH` object (not part of the public
  data contract — use [`field_h`](@ref)/[`field_min_h`](@ref) to query it)
"""
struct LocalSizeField
    pmin::NTuple{3,Float64}
    pmax::NTuple{3,Float64}
    global_h::Float64
    refine_at::Vector{Tuple{NTuple{3,Float64},Float64}}
    handle::Any
end

function Base.show(io::IO, f::LocalSizeField)
    print(io, "LocalSizeField(global_h=", f.global_h,
          ", box=", f.pmin, "..", f.pmax,
          ", refine_at=", length(f.refine_at), " points)")
end

_as_point3d(p::NTuple{3,<:Real}) = Internals.Point3d(Float64(p[1]), Float64(p[2]), Float64(p[3]))
_as_point3d(p::AbstractVector{<:Real}) =
    length(p) == 3 ? Internals.Point3d(Float64(p[1]), Float64(p[2]), Float64(p[3])) :
    length(p) == 2 ? Internals.Point3d(Float64(p[1]), Float64(p[2]), 0.0) :
    throw(ArgumentError("point must have length 2 or 3 (got $(length(p)))"))
_as_point3d(p::Tuple{<:Real,<:Real}) = Internals.Point3d(Float64(p[1]), Float64(p[2]), 0.0)
_as_ntuple3(p) = length(p) == 3 ? (Float64(p[1]), Float64(p[2]), Float64(p[3])) :
                 length(p) == 2 ? (Float64(p[1]), Float64(p[2]), 0.0) :
                 throw(ArgumentError("point must have length 2 or 3 (got $(length(p)))"))

"""
    local_size_field(pmin, pmax, global_h; refine_at=[]) -> LocalSizeField

Build a standalone [`LocalSizeField`](@ref) over the box `pmin..pmax` with
background size `global_h`, applying `refine_at` as a list of `(point, h)`
overrides (each `point` a length-2 or length-3 real vector/tuple; `h > 0`).

`global_h` must be `> 0`. Overrides are applied in order via `Internals.SetH`;
later overrides at the same location win.
"""
function local_size_field(pmin, pmax, global_h::Real; refine_at=Tuple{Any,Float64}[])
    global_h > 0 || throw(ArgumentError("local_size_field: global_h must be > 0 (got $global_h)"))
    handle = Internals.new_localh(_as_point3d(pmin), _as_point3d(pmax), Float64(global_h))
    applied = Tuple{NTuple{3,Float64},Float64}[]
    for (pt, h) in refine_at
        h > 0 || throw(ArgumentError("local_size_field: refine_at size must be > 0 (got $h at $pt)"))
        Internals.SetH(handle, _as_point3d(pt), Float64(h))
        push!(applied, (_as_ntuple3(pt), Float64(h)))
    end
    return LocalSizeField(_as_ntuple3(pmin), _as_ntuple3(pmax), Float64(global_h), applied, handle)
end

"""
    restrict_h!(field::LocalSizeField, point, h) -> field

Override the mesh size at `point` to `h` (`Internals.SetH`). `h` must be `> 0`.
"""
function restrict_h!(f::LocalSizeField, point, h::Real)
    h > 0 || throw(ArgumentError("restrict_h!: h must be > 0 (got $h)"))
    Internals.SetH(f.handle, _as_point3d(point), Float64(h))
    push!(f.refine_at, (_as_ntuple3(point), Float64(h)))
    return f
end

"""
    field_h(field::LocalSizeField, point) -> Float64

Query the current size at `point` (`Internals.GetH`).
"""
field_h(f::LocalSizeField, point) = Internals.GetH(f.handle, _as_point3d(point))

"""
    field_min_h(field::LocalSizeField, pmin, pmax) -> Float64

Minimum size over the box `pmin..pmax` (`Internals.GetMinH`).
"""
field_min_h(f::LocalSizeField, pmin, pmax) =
    Internals.GetMinH(f.handle, _as_point3d(pmin), _as_point3d(pmax))

# --- mesh-level h-field operations -------------------------------------------

"""
    restrict_h!(mesh, point, h) -> mesh

Best-effort local size annotation on an existing `mesh` (`Internals.RestrictLocalH`).
Immediately visible to [`mesh_h_at`](@ref) queries and to post-generation passes
that consult the mesh's local-h field (e.g. `optimize_volume!`), but — in this
build — does **not** retroactively change element sizes produced by
[`generate_mesh`](@ref), since `GenerateMesh` recomputes its own local-h field
during surface meshing. To actually get finer elements near a point, use
`MeshOptions(local_size=...)` (mark-and-bisect refinement) or call
[`refine_near!`](@ref) after generation.
"""
function restrict_h!(m, point, h::Real)
    h > 0 || throw(ArgumentError("restrict_h!: h must be > 0 (got $h)"))
    Internals.RestrictLocalH(m, _as_point3d(point), Float64(h))
    return m
end

"""
    restrict_h_at!(mesh, points::AbstractMatrix, hs::AbstractVector) -> mesh

Bulk convenience over [`restrict_h!`](@ref): `points` is `2×n` or `3×n` (one
column per point), `hs` is length `n`. Throws `ArgumentError` on shape mismatch.
"""
function restrict_h_at!(m, points::AbstractMatrix{<:Real}, hs::AbstractVector{<:Real})
    d, n = size(points)
    d in (2, 3) || throw(ArgumentError("restrict_h_at!: points must have 2 or 3 rows (got $d)"))
    length(hs) == n ||
        throw(ArgumentError("restrict_h_at!: hs length ($(length(hs))) must match number of points ($n)"))
    for j in 1:n
        restrict_h!(m, view(points, :, j), hs[j])
    end
    return m
end

"""
    mesh_h_at(mesh, point) -> Float64

Current local-h field value at `point` (`Internals.GetH`). For a specific
existing mesh vertex by 1-based index, see [`mesh_h_at_point`](@ref).
"""
mesh_h_at(m, point) = Internals.GetH(m, _as_point3d(point))

"""
    set_global_h!(mesh, h) -> mesh

Set the mesh's global/background target size (`Internals.SetGlobalH`). `h` must
be `> 0`.
"""
function set_global_h!(m, h::Real)
    h > 0 || throw(ArgumentError("set_global_h!: h must be > 0 (got $h)"))
    Internals.SetGlobalH(m, Float64(h))
    return m
end

"""
    set_minimal_h!(mesh, h) -> mesh

Set the mesh's minimum allowed size (`Internals.SetMinimalH`). `h` must be `> 0`.
"""
function set_minimal_h!(m, h::Real)
    h > 0 || throw(ArgumentError("set_minimal_h!: h must be > 0 (got $h)"))
    Internals.SetMinimalH(m, Float64(h))
    return m
end

# --- the mechanism that actually works: mark + bisect near a point ----------

"""
    refine_near!(mesh, point; radius, levels=1) -> mesh

Locally refine `mesh` near `point` by marking every element whose centroid
lies within `radius` of `point` and running [`bisect!`](@ref), repeated
`levels` times (each pass roughly halves local element size). This is the
mechanism [`MeshOptions`](@ref)'s `local_size` option is built on, since
Netgen's `RestrictLocalH`/`SetLocalH` do not feed back into this package's
`generate_mesh` entry point (see the module notes in `local_sizing.jl`).

`radius` must be `> 0`; `levels` must be `>= 1`. Each additional level roughly
doubles element count *within* `radius`, so `levels >= 3` can blow up total
element count quickly on a large mesh; `levels=2` was observed (on curved/thin
geometry) to occasionally produce a handful of inverted elements that Netgen's
`CheckVolumeMesh` flags as warnings without failing — check `validate(mesh)`
after aggressive local refinement.

# Dimension-dependent effectiveness (verified empirically, not theoretical)

- **3D**: marking has a real, measurable localizing effect on top of
  [`bisect!`](@ref)'s mostly-uniform base refinement — elements near `point`
  end up noticeably denser than an identical unmarked bisection pass at the
  same location (roughly 30–75% shorter edges and 2–4× more elements in the
  same radius in the geometry this was checked against).
- **2D**: in this build, [`bisect!`](@ref) refines uniformly regardless of
  `mark_for_refinement!` — marking a subset of triangles produces an
  *identical* result (same element count, same edge lengths everywhere) to
  marking nothing. `refine_near!` still runs (so `MeshOptions.local_size` does
  not error in 2D) but currently only achieves the *global* uniform refinement
  that `levels` requests, not a spatially localized one; it emits a one-time
  `@warn` the first time it is called on a 2D mesh in a session.
"""
function refine_near!(m, point; radius::Real, levels::Integer=1)
    radius > 0 || throw(ArgumentError("refine_near!: radius must be > 0 (got $radius)"))
    levels >= 1 || throw(ArgumentError("refine_near!: levels must be >= 1 (got $levels)"))
    center = collect(_as_ntuple3(point))
    d = mesh_dimension(m)
    _warn_if_2d_localization_ineffective(d)
    for _ in 1:levels
        X = points(m)
        T = d == 3 ? tetrahedra(m) : triangles2d(m)
        ne = size(T, 2)
        marked = falses(ne)
        nv = size(T, 1)
        for e in 1:ne
            c = sum(X[:, T[i, e]] for i in 1:nv) ./ nv
            marked[e] = sqrt(sum((c .- center) .^ 2)) <= radius
        end
        mark_for_refinement!(m, marked)
        bisect!(m)
    end
    return m
end

let warned = Ref(false)
    global function _warn_if_2d_localization_ineffective(d::Integer)
        if d == 2 && !warned[]
            warned[] = true
            @warn "refine_near!/MeshOptions.local_size: in this build, 2D bisect! refines uniformly regardless of marked elements, so local refinement near a point is not spatially localized in 2D (3D is unaffected). See the refine_near! docstring."
        end
        return nothing
    end
end

"""
    refine_near!(mesh, points::AbstractVector; radius, levels=1) -> mesh

Refine near each of several points in a single pass per level (elements within
`radius` of *any* listed point are marked together, rather than iterating
[`refine_near!`](@ref) point-by-point). See the single-point [`refine_near!`](@ref)
docstring for the 2D-vs-3D effectiveness caveat.
"""
function refine_near!(m, pts::AbstractVector; radius::Real, levels::Integer=1)
    radius > 0 || throw(ArgumentError("refine_near!: radius must be > 0 (got $radius)"))
    levels >= 1 || throw(ArgumentError("refine_near!: levels must be >= 1 (got $levels)"))
    centers = [collect(_as_ntuple3(p)) for p in pts]
    d = mesh_dimension(m)
    _warn_if_2d_localization_ineffective(d)
    for _ in 1:levels
        X = points(m)
        T = d == 3 ? tetrahedra(m) : triangles2d(m)
        ne = size(T, 2)
        nv = size(T, 1)
        marked = falses(ne)
        for e in 1:ne
            c = sum(X[:, T[i, e]] for i in 1:nv) ./ nv
            marked[e] = any(center -> sqrt(sum((c .- center) .^ 2)) <= radius, centers)
        end
        mark_for_refinement!(m, marked)
        bisect!(m)
    end
    return m
end
