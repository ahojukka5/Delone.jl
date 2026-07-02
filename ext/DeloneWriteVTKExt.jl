# --- Delone <-> WriteVTK package extension ------------------------------------
# Loaded automatically (Base.get_extension) when the host session has both
# Delone and WriteVTK loaded. See Project.toml [weakdeps]/[extensions].
# Requires Julia >= 1.9.
#
# `export_vtk` (src/export_mesh.jl) is Delone's always-available, dependency-
# free ASCII VTK writer — it stays untouched and remains the fallback when
# WriteVTK is not installed. This extension adds `export_vtu`, a real
# binary/compressed `.vtu` (XML VTK Unstructured Grid) writer built on top of
# `WriteVTK.jl`, with per-cell data (region/material id, boundary region id)
# attached — the value-add `export_vtk` cannot provide without a real VTK
# dependency.
#
# Like DeloneMakieExt, this extension prefers Delone's dependency-free,
# plain-array snapshot type (`MeshLevelSnapshot` from src/snapshots.jl) as the
# primary input, since live mesh handles returned by
# `generate_mesh`/`mesh_session` are raw, unexported
# `Delone.Netgen` C++ handles (`CxxWrap.StdLib.SharedPtrAllocated{...}`) —
# not a stable public type to dispatch on, and AGENTS.md says public code must
# never leak raw `Netgen` handles into dispatch surfaces. Unlike the Makie
# extension, though, `export_vtu` *also* accepts a live mesh handle directly
# (any `m` for which the existing, dimension-generic extraction functions
# `points`/`mesh_dimension`/`tetrahedra`/`triangles2d`/`surface_triangles`/
# `segments2d`/`cell_regions`/`boundary_regions` work) via a duck-typed
# fallback method, mirroring how `export_vtk` itself already accepts live
# handles. This is convenient because taking a full `level_snapshot` first is
# unnecessary overhead for a one-shot file export.
#
# Per-element quality data (e.g. from `quality(mesh)`) is *not* included as
# cell data here: `MeshQualityReport`/`NativeQualityReport` only expose
# aggregate statistics (min/max/mean/quantiles) — the per-element arrays
# (`qualities` in `quality.jl`'s `quality(m)`, `errs` in `native_quality(m)`)
# are computed internally but never returned or stored on any public struct
# or snapshot field. Exposing them would require adding a new per-element
# quality API to Delone itself (e.g. a `per_element_quality(mesh)` function or
# a new `MeshLevelSnapshot` field), which is out of scope for this extension
# to invent unilaterally. Noted here as a limitation rather than silently
# skipped.
module DeloneWriteVTKExt

using Delone
using Delone: MeshLevelSnapshot
using WriteVTK

# --- shared helpers -----------------------------------------------------------

"""
    _vtu_mesh_data(m) -> NamedTuple

Common extraction shape consumed by [`Delone.export_vtu`](@ref):
`(dim, coords, vol_conn, surf_conn, cell_regions, boundary_regions)`.

- `coords` is always `3 × nnodes` (VTK points are always 3D; 2D snapshots/
  meshes get a `z = 0` row appended).
- `vol_conn` is the top-dimensional cell connectivity (`4×ne` tets in 3D,
  `3×ne` triangles in 2D), `surf_conn` the boundary facet connectivity (`3×nse`
  triangles in 3D, `2×nseg` segments in 2D) — both one-based, matching
  `MeshLevelSnapshot`/`tetrahedra`/`surface_triangles` conventions.

Two families of methods: `MeshLevelSnapshot{2}`/`MeshLevelSnapshot{3}` read
plain struct fields directly; the generic fallback calls Delone's existing,
dimension-generic extraction functions on a live mesh handle (or anything
else that supports them), exactly like `export_vtk` already does.
"""
function _vtu_mesh_data(m::MeshLevelSnapshot{3})
    return (dim=3, coords=m.coordinates, vol_conn=m.volume_connectivity,
            surf_conn=m.surface_connectivity, cell_regions=m.cell_regions,
            boundary_regions=m.boundary_regions)
end

function _vtu_mesh_data(m::MeshLevelSnapshot{2})
    np = size(m.coordinates, 2)
    coords = vcat(m.coordinates, zeros(eltype(m.coordinates), 1, np))  # lift to z=0
    return (dim=2, coords=coords, vol_conn=m.volume_connectivity,
            surf_conn=m.surface_connectivity, cell_regions=m.cell_regions,
            boundary_regions=m.boundary_regions)
end

_vtu_mesh_data(m::MeshLevelSnapshot{Dim}) where {Dim} = throw(ArgumentError(
    "export_vtu for MeshLevelSnapshot only supports Dim in (2, 3); got Dim=$Dim"))

# Fallback: any live mesh handle (or other object) supporting Delone's
# existing dimension-generic extraction functions. `points(m)` already
# returns 3×np (Netgen always stores 3 coordinates internally, even in 2D).
function _vtu_mesh_data(m)
    d = Delone.mesh_dimension(m)
    coords = Delone.points(m)
    if d == 3
        vol = Delone.tetrahedra(m)
        surf = Delone.surface_triangles(m)
    elseif d == 2
        vol = Delone.triangles2d(m)
        surf = Delone.segments2d(m)
    else
        throw(ArgumentError("export_vtu: unsupported mesh dimension $d (need 2 or 3)"))
    end
    return (dim=d, coords=coords, vol_conn=vol, surf_conn=surf,
            cell_regions=Delone.cell_regions(m), boundary_regions=Delone.boundary_regions(m))
end

"""
    _vtu_cells_and_data(data; include_volume, include_surface)

Build the `WriteVTK.MeshCell` vector plus parallel cell-data arrays
(`region`, `boundary_region`, `is_boundary`) for one combined VTU piece
containing volume cells (tets in 3D / triangles in 2D) followed by boundary
cells (triangles in 3D / line segments in 2D). Volume cells get their
`cell_regions` value in `region` and `0` in `boundary_region`; boundary cells
get the reverse, plus `is_boundary` distinguishes the two blocks (`1` for a
boundary facet, `0` for a volume/domain cell) since ParaView-style viewers
otherwise cannot tell a `0`-region volume cell apart from a `0`-region
boundary cell.
"""
function _vtu_cells_and_data(data; include_volume::Bool, include_surface::Bool)
    cells = WriteVTK.MeshCell[]
    region = Int32[]
    boundary_region = Int32[]
    is_boundary = Int32[]

    if include_volume
        vt = data.dim == 3 ? WriteVTK.VTKCellTypes.VTK_TETRA : WriteVTK.VTKCellTypes.VTK_TRIANGLE
        for e in axes(data.vol_conn, 2)
            push!(cells, WriteVTK.MeshCell(vt, Int64.(data.vol_conn[:, e])))
            push!(region, data.cell_regions[e])
            push!(boundary_region, Int32(0))
            push!(is_boundary, Int32(0))
        end
    end
    if include_surface
        st = data.dim == 3 ? WriteVTK.VTKCellTypes.VTK_TRIANGLE : WriteVTK.VTKCellTypes.VTK_LINE
        for e in axes(data.surf_conn, 2)
            push!(cells, WriteVTK.MeshCell(st, Int64.(data.surf_conn[:, e])))
            push!(region, Int32(0))
            push!(boundary_region, data.boundary_regions[e])
            push!(is_boundary, Int32(1))
        end
    end
    return cells, region, boundary_region, is_boundary
end

# --- public entry point --------------------------------------------------------

"""
    export_vtu(mesh_or_snapshot, path; include_volume=true, include_surface=true) -> String

Write a real binary/compressed VTU (`.vtu`, XML VTK UnstructuredGrid) file via
`WriteVTK.jl`, with per-cell data attached:

- `region` — [`cell_regions`](@ref) (material/sub-domain id) for volume cells,
  `0` for boundary cells.
- `boundary_region` — [`boundary_regions`](@ref) (face/segment descriptor id)
  for boundary cells, `0` for volume cells.
- `is_boundary` — `1` for a boundary facet, `0` for a volume/domain cell (lets
  a viewer separate the two `region`/`boundary_region` value spaces).

Accepts either a [`MeshLevelSnapshot`](@ref) (3D tets + triangle facets, or 2D
triangles + segment facets) or a live mesh handle (anything supporting
[`points`](@ref)/[`mesh_dimension`](@ref)/[`tetrahedra`](@ref)/
[`surface_triangles`](@ref)/`triangles2d`/`segments2d`/[`cell_regions`](@ref)/
[`boundary_regions`](@ref)) — mirroring [`export_vtk`](@ref)'s acceptance of
either. `path` is passed straight to `WriteVTK.vtk_grid`, which appends
`.vtu` itself if missing. Returns the actual file path written.

Requires `WriteVTK` to be loaded (`using WriteVTK`) to activate this
extension; use [`export_vtk`](@ref) for the dependency-free ASCII fallback
that is always available.

Per-element quality data (e.g. from [`quality`](@ref)) is not included — see
the module-level comment in `DeloneWriteVTKExt` for why.
"""
function Delone.export_vtu(m, path::AbstractString;
                            include_volume::Bool=true, include_surface::Bool=true)
    data = _vtu_mesh_data(m)
    cells, region, boundary_region, is_boundary =
        _vtu_cells_and_data(data; include_volume, include_surface)

    vtk = WriteVTK.vtk_grid(path, data.coords, cells)
    vtk["region", WriteVTK.VTKCellData()] = region
    vtk["boundary_region", WriteVTK.VTKCellData()] = boundary_region
    vtk["is_boundary", WriteVTK.VTKCellData()] = is_boundary
    outfiles = WriteVTK.vtk_save(vtk)
    return only(outfiles)
end

end # module DeloneWriteVTKExt
