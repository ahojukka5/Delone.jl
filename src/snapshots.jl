# --- snapshot data contract --------------------------------------------------
# Consumer-agnostic, plain-array COPIES of a live session. Snapshots are derived
# views: mutating a snapshot never touches the authoritative live Netgen handles
# (see session.jl). All ids are one-based (see the audit doc, §4).

"""
    MeshLevelSnapshot{Dim,T,I}

Copied, plain-array description of one mesh level. `Dim` is the topological
dimension (2 or 3), `T` the coordinate eltype (`Float64`), `I` the connectivity
integer type (`Int32`).

- `coordinates::Matrix{T}` — `Dim × nnodes`, one-based node columns.
- `volume_connectivity::Matrix{I}` — top-dimensional cells (`4×ne` tets in 3D,
  `3×nse` triangles in 2D), one-based node ids.
- `surface_connectivity::Matrix{I}` — boundary facets (`3×nse` triangles in 3D,
  `2×nseg` segments in 2D), one-based node ids.
- `cell_regions::Vector{Int32}` — per cell region id (see [`cell_regions`](@ref)).
- `boundary_regions::Vector{Int32}` — per facet region id (see [`boundary_regions`](@ref)).
- `material_names::Dict{Int32,String}` — region id → material name.
- `boundary_names::Dict{Int32,String}` — region id → boundary name.
- `element_type::Symbol` — `:tet` (3D) or `:tri` (2D).
- `boundary_element_type::Symbol` — `:tri` (3D) or `:segment` (2D).
- `level::Int` — one-based level index within the session.
- `generation::Int` — session generation at snapshot time.
"""
struct MeshLevelSnapshot{Dim,T,I}
    coordinates::Matrix{T}
    volume_connectivity::Matrix{I}
    surface_connectivity::Matrix{I}
    cell_regions::Vector{Int32}
    boundary_regions::Vector{Int32}
    material_names::Dict{Int32,String}
    boundary_names::Dict{Int32,String}
    element_type::Symbol
    boundary_element_type::Symbol
    level::Int
    generation::Int
end

"""
    HierarchyTransferSnapshot{I,T}

Copied description of the coarse→fine transition from `level_from` to `level_to`
(`level_to == level_from + 1`). All ids are one-based in the respective level's
snapshot arrays, with `0` = none.

- `parent_nodes::Matrix{I}` — `2 × nnodes(level_to)`; the two coarse parents of
  each fine node, `(0,0)` for an inherited node.
- `parent_elements::Vector{I}` — per fine cell, its coarse parent (`0` if none).
- `parent_surface_elements::Vector{I}` — per fine facet, its coarse parent.
- `weights::Union{Nothing,Matrix{T}}` — exact interpolation weights, or `nothing`
  when unavailable. When `nothing`, the consumer should use topological 1/2–1/2
  nodal interpolation on the bisection parent-node map.
"""
struct HierarchyTransferSnapshot{I,T}
    level_from::Int
    level_to::Int
    parent_nodes::Matrix{I}
    parent_elements::Vector{I}
    parent_surface_elements::Vector{I}
    weights::Union{Nothing,Matrix{T}}
end

"""
    MeshHierarchySnapshot

All level snapshots and all transfer snapshots of a session, plus the session
`generation` at snapshot time. `transfers[k]` describes `levels[k] → levels[k+1]`.
"""
struct MeshHierarchySnapshot
    levels::Vector{MeshLevelSnapshot}
    transfers::Vector{HierarchyTransferSnapshot}
    generation::Int
end

"""
    level_snapshot(session, k) -> MeshLevelSnapshot

Copied plain-array snapshot of live level `k` (one-based). Coordinates,
volume/boundary connectivity, region ids, material/boundary names, element types,
level and session generation. `k` must be in `1:nlevels(session)`. Supports 2D
and 3D meshes; other dimensions throw `ArgumentError`.
"""
function level_snapshot(s::MeshHierarchySession, k::Integer)
    1 <= k <= nlevels(s) ||
        throw(ArgumentError("level $k out of range 1:$(nlevels(s))"))
    m = s.meshes[k]
    dim = Int(GetDimension(m))
    dim in (2, 3) ||
        throw(ArgumentError("level_snapshot: unsupported mesh dimension $dim"))
    X = points(m)                       # 3×np (Netgen stores 3 coords)
    coords = Matrix{Float64}(X[1:dim, :])
    if dim == 3
        vol = volume_tetrahedra(m)
        surf = surface_triangles(m)
        etype, btype = :tet, :tri
    else
        vol = triangles2d(m)
        surf = segments2d(m)
        etype, btype = :tri, :segment
    end
    return MeshLevelSnapshot{dim,Float64,Int32}(
        coords, vol, surf,
        cell_regions(m), boundary_regions(m),
        material_names(m), boundary_names(m),
        etype, btype, Int(k), s.generation)
end

"""
    transfer_snapshot(session, k) -> HierarchyTransferSnapshot

Copied coarse→fine transition from level `k-1` to level `k` (parent-node,
parent-element and parent-surface-element maps of live level `k`). `weights` is
`nothing` (use topological 1/2–1/2 nodal interpolation). `k` must be ≥ 2 and
≤ `nlevels(session)`; `transfer_snapshot(session, 1)` throws `ArgumentError`.
"""
function transfer_snapshot(s::MeshHierarchySession, k::Integer)
    k >= 2 || throw(ArgumentError(
        "transfer_snapshot is defined for levels k ≥ 2 (got $k); " *
        "level 1 has no coarser parent level"))
    k <= nlevels(s) ||
        throw(ArgumentError("level $k out of range 2:$(nlevels(s))"))
    m = s.meshes[k]
    return HierarchyTransferSnapshot{Int32,Float64}(
        k - 1, k,
        parent_nodes(m),
        parent_elements(m),
        parent_surface_elements(m),
        nothing)
end

"""
    hierarchy_snapshot(session) -> MeshHierarchySnapshot

All level snapshots (`1:nlevels`) and all transfer snapshots (`2:nlevels`) of the
session, tagged with the current `generation`.
"""
function hierarchy_snapshot(s::MeshHierarchySession)
    levels = MeshLevelSnapshot[level_snapshot(s, k) for k in 1:nlevels(s)]
    transfers = HierarchyTransferSnapshot[transfer_snapshot(s, k) for k in 2:nlevels(s)]
    return MeshHierarchySnapshot(levels, transfers, s.generation)
end
