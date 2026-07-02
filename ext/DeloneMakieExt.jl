# --- Delone <-> Makie package extension --------------------------------------
# Loaded automatically (Base.get_extension) when the host session has both
# Delone and Makie (or a Makie backend such as CairoMakie/GLMakie) loaded.
# See Project.toml [weakdeps]/[extensions]. Requires Julia >= 1.9.
#
# Only Delone's dependency-free, plain-array snapshot types
# (`MeshLevelSnapshot`, `MeshHierarchySnapshot` from src/snapshots.jl) are
# supported here. Live mesh handles returned by `generate_mesh`/`mesh_session`
# are `CxxWrap.StdLib.SharedPtrAllocated{Delone.Internals.Mesh}` — a raw,
# unexported `Internals` C++ handle type, not a stable Delone-owned type to
# dispatch a public recipe on (and AGENTS.md explicitly says public code must
# never leak raw `Internals` handles). Take a snapshot first
# (`level_snapshot`/`hierarchy_snapshot`) and plot that instead.
module DeloneMakieExt

using Delone
using Delone: MeshLevelSnapshot, MeshHierarchySnapshot
using Makie

# --- shared helpers -----------------------------------------------------------

# `Makie.mesh` wants Npoints x Dim vertices and Nfaces x 3 (1-based) face
# index matrices; Delone snapshots store the transpose of both (Dim x
# Npoints, 3/4 x Ncells), so every recipe below just transposes on the way in.
# No GeometryBasics types are constructed here (that bridge is deferred to a
# future DeloneGeometryBasicsExt); Makie's own `mesh` recipe accepts plain
# coordinate/face matrices directly.

"""
    _mesh_verts_faces(m::MeshLevelSnapshot{3}) -> (verts, faces)

Boundary surface triangulation of a 3D snapshot: `verts` is `nnodes x 3`
(`m.coordinates` transposed) and `faces` is `nse x 3` (`m.surface_connectivity`
transposed, already 1-based). Tetrahedra themselves are not directly
renderable as a `Makie.mesh` — the boundary facets are what gets drawn.
"""
function _mesh_verts_faces(m::MeshLevelSnapshot{3})
    verts = permutedims(m.coordinates)
    faces = permutedims(m.surface_connectivity)
    return verts, faces
end

"""
    _mesh_verts_faces(m::MeshLevelSnapshot{2}) -> (verts, faces)

Flat domain triangulation of a 2D snapshot: `verts` is `nnodes x 3` (the 2D
`m.coordinates` transposed and lifted to `z = 0`) and `faces` is `ntri x 3`
(`m.volume_connectivity` transposed, already 1-based).
"""
function _mesh_verts_faces(m::MeshLevelSnapshot{2})
    z = zeros(eltype(m.coordinates), 1, size(m.coordinates, 2))
    verts = permutedims(vcat(m.coordinates, z))
    faces = permutedims(m.volume_connectivity)
    return verts, faces
end

_mesh_verts_faces(m::MeshLevelSnapshot{Dim}) where {Dim} = throw(ArgumentError(
    "Makie recipes for MeshLevelSnapshot only support Dim in (2, 3); got Dim=$Dim"))

# --- MeshLevelSnapshot recipes -------------------------------------------------

"""
    Makie.mesh(m::MeshLevelSnapshot; kwargs...)

Render one mesh level snapshot as a `Makie.mesh` plot. 3D snapshots
(`Dim == 3`) draw the boundary surface triangulation
(`m.surface_connectivity`); 2D snapshots (`Dim == 2`) draw the flat domain
triangulation (`m.volume_connectivity`) lifted onto `z = 0`. Returns a
`Makie.FigureAxisPlot` (the same object `Makie.mesh(verts, faces)` returns).
`kwargs` are forwarded to `Makie.mesh` (e.g. `color`, `shading`, `colormap`).
"""
function Makie.mesh(m::MeshLevelSnapshot; kwargs...)
    verts, faces = _mesh_verts_faces(m)
    return Makie.mesh(verts, faces; kwargs...)
end

"""
    Makie.mesh!(ax, m::MeshLevelSnapshot; kwargs...)

In-place variant of [`Makie.mesh(::MeshLevelSnapshot)`](@ref) — draws into an
existing `Axis`/`Axis3`/`Scene` instead of creating a new `Figure`.
"""
function Makie.mesh!(ax, m::MeshLevelSnapshot; kwargs...)
    verts, faces = _mesh_verts_faces(m)
    return Makie.mesh!(ax, verts, faces; kwargs...)
end

"""
    Makie.plot(m::MeshLevelSnapshot; kwargs...)

Alias for [`Makie.mesh(::MeshLevelSnapshot)`](@ref) so `plot(snapshot)` works
as the generic entry point mesh viewers expect. Returns a `Makie.FigureAxisPlot`.
"""
Makie.plot(m::MeshLevelSnapshot; kwargs...) = Makie.mesh(m; kwargs...)

# --- MeshHierarchySnapshot convenience -----------------------------------------

"""
    Makie.mesh(h::MeshHierarchySnapshot; level::Integer=length(h.levels), kwargs...)

Render a single level of a mesh hierarchy snapshot (default: the finest
level). Delegates to [`Makie.mesh(::MeshLevelSnapshot)`](@ref).
"""
function Makie.mesh(h::MeshHierarchySnapshot; level::Integer=length(h.levels), kwargs...)
    1 <= level <= length(h.levels) || throw(ArgumentError(
        "level $level out of range 1:$(length(h.levels))"))
    return Makie.mesh(h.levels[level]; kwargs...)
end

"""
    Makie.plot(h::MeshHierarchySnapshot; level::Integer=length(h.levels), kwargs...)

Alias for [`Makie.mesh(::MeshHierarchySnapshot)`](@ref).
"""
Makie.plot(h::MeshHierarchySnapshot; kwargs...) = Makie.mesh(h; kwargs...)

end # module DeloneMakieExt
