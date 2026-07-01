# --- live mesh-hierarchy session --------------------------------------------
# A MeshHierarchySession is the *authoritative*, mutable, geometry-backed live
# handle a consumer keeps during a simulation. It owns the Netgen geometry and a
# stack of live Netgen mesh handles (one per level), a generation counter that is
# bumped on every mutating request, and a free-form metadata dictionary. Copied
# snapshots (see snapshots.jl) are derived views for consumers; the live handles
# here remain authoritative.

"""
    MeshHierarchySession

Live, geometry-backed mesh hierarchy — the authoritative state a consumer keeps
during a simulation.

Fields:
- `geometry` — the shared Netgen/OCC geometry backing every level.
- `meshes::Vector{Any}` — live Netgen mesh handles, one per level, coarsest
  first. `meshes[end]` is the current finest level.
- `generation::Int` — bumped by **every** mutating request. Lets a consumer
  detect that the live hierarchy changed since a snapshot was taken.
- `metadata::Dict{Symbol,Any}` — free-form (e.g. `:maxh`, `:curved_order`).

Semantics:
- it stores **live** Netgen geometry and mesh handles (not copies);
- it can grow during a simulation via the `request_*!` functions;
- it preserves access to every previous level;
- it can hand out copied snapshots on demand ([`level_snapshot`](@ref),
  [`transfer_snapshot`](@ref), [`hierarchy_snapshot`](@ref));
- snapshots are **not** authoritative — the live mesh handles are.

Construct with [`mesh_session`](@ref).
"""
mutable struct MeshHierarchySession
    geometry::Any
    meshes::Vector{Any}
    generation::Int
    metadata::Dict{Symbol,Any}
end

Base.length(s::MeshHierarchySession) = length(s.meshes)
Base.getindex(s::MeshHierarchySession, k::Integer) = s.meshes[k]
Base.lastindex(s::MeshHierarchySession) = length(s.meshes)
Base.iterate(s::MeshHierarchySession, i=1) =
    i > length(s.meshes) ? nothing : (s.meshes[i], i + 1)

"""
    mesh_session(geometry; maxh, kwargs...) -> MeshHierarchySession

Start a live hierarchy with a single coarse mesh of `geometry` (level 1) meshed
at `maxh`. Any extra `kwargs` are stored verbatim in `metadata`. The session's
`generation` starts at `0`. Grow it during the simulation with
[`request_uniform_refinement!`](@ref) / [`request_marked_refinement!`](@ref).
"""
function mesh_session(geometry; maxh::Real, kwargs...)
    m = generate_mesh(geometry; maxh=maxh)
    meta = Dict{Symbol,Any}(:maxh => Float64(maxh))
    for (k, v) in kwargs
        meta[k] = v
    end
    return MeshHierarchySession(geometry, Any[m], 0, meta)
end

"""nlevels(session) -> number of live mesh levels currently in the session."""
nlevels(s::MeshHierarchySession) = length(s.meshes)

"""coarsest(session) / finest(session) -> the coarsest / finest live mesh handle."""
coarsest(s::MeshHierarchySession) = s.meshes[1]
finest(s::MeshHierarchySession) = s.meshes[end]

"""
    level_mesh(session, k) -> live Netgen mesh handle for level `k` (1-based).

Returns the **authoritative live** mesh handle, not a copy. Mutating it mutates
the session's level. `k` must be in `1:nlevels(session)`.
"""
function level_mesh(s::MeshHierarchySession, k::Integer)
    1 <= k <= nlevels(s) ||
        throw(ArgumentError("level $k out of range 1:$(nlevels(s))"))
    return s.meshes[k]
end

"""geometry(session) -> the shared geometry backing every level."""
geometry(s::MeshHierarchySession) = s.geometry

"""generation(session) -> the mutation counter (bumped by every `request_*!`)."""
generation(s::MeshHierarchySession) = s.generation

# --- refinement requests (mutating; each bumps generation) ------------------

"""
    request_uniform_refinement!(session) -> session

Append a new finest level: a uniformly, geometry-aware refined copy of the
current finest mesh (`Refinement::Refine`). Previous levels are preserved.
Increments `generation(session)`.
"""
function request_uniform_refinement!(s::MeshHierarchySession)
    m = copy_mesh(finest(s))
    refine!(m)
    push!(s.meshes, m)
    s.generation += 1
    return s
end

"""
    request_marked_refinement!(session, marked; onlyonce=false, maxlevel=0) -> session

Append a new finest level by element-wise, geometry-aware **bisection** of a copy
of the current finest mesh. `marked` is indexed by the **current finest level's
volume elements** (`1:GetNE(finest(session))` for 3D; a `Bool` vector /
predicate from an error indicator). Netgen adds conforming closure refinement as
needed. Previous levels are preserved. Increments `generation(session)`.

`onlyonce`/`maxlevel` are forwarded to `bisect!` / `BisectionOptions`.
"""
function request_marked_refinement!(s::MeshHierarchySession, marked;
                                    onlyonce::Bool=false, maxlevel::Integer=0)
    m = copy_mesh(finest(s))
    UpdateTopology(m)
    mark_for_refinement!(m, marked)
    bisect!(m; onlyonce=onlyonce, maxlevel=maxlevel)
    push!(s.meshes, m)
    s.generation += 1
    return s
end

"""
    request_second_order!(session; order=2) -> session

**Behavior (documented choice): curves the current finest mesh in place — it does
NOT append a new level.** Second-order curving is a p-type change to the existing
topological level (edge-midpoint nodes projected onto the true geometry), so it
belongs to the same h-level rather than being a new refinement level. Increments
`generation(session)` and records `metadata[:curved_order]`.

Only `order == 2` is supported (via `Refinement::MakeSecondOrder`). Higher-order
curving through `Mesh::BuildCurvedElements` / `Ngx_Mesh::Curve` is deferred; a
call with `order != 2` throws `ArgumentError`.
"""
function request_second_order!(s::MeshHierarchySession; order::Integer=2)
    order == 2 || throw(ArgumentError(
        "request_second_order! currently supports order=2 only (got $order); " *
        "higher-order curving via BuildCurvedElements/Curve is deferred"))
    make_second_order!(finest(s))
    s.metadata[:curved_order] = Int(order)
    s.generation += 1
    return s
end
