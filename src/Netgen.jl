"""
    Netgen

A CxxWrap-based Julia binding and extension layer for the exported C++ API of
NGSolve/Netgen, with Julia-side utilities for geometry-backed mesh hierarchies
and geometric-multigrid / hp-adaptivity integration.

The native binding (`NetgenCxxWrap_jll` / `libnetgen_cxxwrap`) is a **strict 1:1**
CxxWrap module: every wrapped name matches Netgen's own C++ name (`GetNP`,
`UpdateTopology`, `GetTopology`, `GetNEdges`, `LoadOCC_STEP`, `GenerateMesh`,
`Refine`, `Point`, `VolumeElement`, `PNum`, …) and forwards to exactly one Netgen
member. **All higher-level logic lives here**, in Julia: composing those calls,
looping to build arrays, and hierarchy helpers.
"""
module Netgen

using CxxWrap
using Libdl
using Artifacts
import OCCT_jll  # OCCT (+ FreeType) must load before libnetgen_cxxwrap (BREP bridge)
import Zlib_jll

const _netgen_dir = artifact"NGSolveNetgen"
const _wrap_dir = artifact"libnetgen_cxxwrap"
const libnetgen_cxxwrap = joinpath(_wrap_dir, "lib", "libnetgen_cxxwrap.$(Libdl.dlext)")

@wrapmodule(() -> libnetgen_cxxwrap)

function __init__()
    flags = Libdl.RTLD_LAZY | Libdl.RTLD_GLOBAL
    Libdl.dlopen(joinpath(_netgen_dir, "lib", "libngcore.$(Libdl.dlext)"), flags)
    Libdl.dlopen(joinpath(_netgen_dir, "lib", "libnglib.$(Libdl.dlext)"), flags)
    @initcxx
end

# Netgen ELEMENT_TYPE ids (for comparing GetType results).
const NG_TET = 20
const NG_TRIG = 10

# Netgen NG_REFINEMENT_TYPE ids (for Ngx_Mesh-style refinement selection).
const NG_REFINE_H = 0
const NG_REFINE_P = 1
const NG_REFINE_HP = 2

# --- geometry loading -------------------------------------------------------
# Thin Julia aliases over the exact 1:1 loaders. Extension dispatch (a higher-
# level convenience) also lives here, not in the C++ wrapper.
load_step(path::AbstractString) = LoadOCC_STEP(String(path))
load_iges(path::AbstractString) = LoadOCC_IGES(String(path))
load_brep(path::AbstractString) = LoadOCC_BREP(String(path))
load_stl(path::AbstractString) = LoadSTL(String(path))
load_splinegeometry2d(path::AbstractString) = LoadSplineGeometry2d(String(path))

function load_geometry(path::AbstractString)
    ext = lowercase(splitext(path)[2])
    ext in (".step", ".stp") && return LoadOCC_STEP(String(path))
    ext == ".brep"           && return LoadOCC_BREP(String(path))
    ext in (".iges", ".igs") && return LoadOCC_IGES(String(path))
    error("unsupported geometry extension: $ext")
end

# --- 2D geometry (geom2d / csg2d) -------------------------------------------
# `Circle`, `Rectangle`, `CSG2d`, the boolean ops `+`/`*`/`-`, and `BC`/`Maxh`/
# `Mat` are wrapped directly from Netgen's geom2d module. `geometry2d(solid)`
# turns a Solid2d (or composite) into a meshable geometry.

"""
    geometry2d(solid) -> geometry

Wrap a `Solid2d` (or a boolean composite of them) into a `SplineGeometry2d` that
can be passed to [`generate_mesh`](@ref) / [`coarse_hierarchy`](@ref). Curved
boundaries (e.g. a [`Circle`](@ref)) are followed under refinement.
"""
function geometry2d(solid)
    g = CSG2d()
    Add(g, solid)
    return GenerateSplineGeometry(g)
end

# --- mesh generation (compose the 1:1 calls) --------------------------------
function generate_mesh(geom; maxh::Real)
    m = new_mesh()
    SetGeometry(m, geom)
    mp = MeshingParameters()
    maxh!(mp, Float64(maxh))
    GenerateMesh(geom, m, mp)
    return m
end

# --- extraction (loop over the 1:1 accessors) -------------------------------
"""points(mesh) -> 3×GetNP Matrix{Float64} of node coordinates (Netgen p(i))."""
function points(m)
    np = GetNP(m)
    P = Matrix{Float64}(undef, 3, np)
    for i in 1:np
        p = Point(m, i)
        P[1, i] = p(0); P[2, i] = p(1); P[3, i] = p(2)
    end
    return P
end

"""tetrahedra(mesh) -> 4×GetNE Matrix{Int32}, 1-based node ids (Element::PNum)."""
function tetrahedra(m)
    ne = GetNE(m)
    T = Matrix{Int32}(undef, 4, ne)
    for i in 1:ne
        e = VolumeElement(m, i)
        for j in 1:4
            T[j, i] = PNum(e, j)
        end
    end
    return T
end

"""surface_triangles(mesh) -> 3×GetNSE Matrix{Int32}, 1-based node ids."""
function surface_triangles(m)
    nse = GetNSE(m)
    S = Matrix{Int32}(undef, 3, nse)
    for i in 1:nse
        e = SurfaceElement(m, i)
        for j in 1:3
            S[j, i] = PNum(e, j)
        end
    end
    return S
end

# --- refinement (compose GetGeometry -> GetRefinement -> Refine) ------------
"""refine!(mesh) -> mesh, refined uniformly in place (geometry-aware)."""
function refine!(m)
    Refine(GetRefinement(GetGeometry(m)), m)
    return m
end

"""
    mark_for_refinement!(mesh, marked) -> mesh

Set each volume element's refinement flag from `marked` (a `1:GetNE`-indexed
boolean vector / predicate); elements not listed are cleared. Use before
[`bisect!`](@ref).
"""
function mark_for_refinement!(m, marked)
    for i in 1:GetNE(m)
        SetRefinementFlag(VolumeElement(m, i), Bool(marked[i]))
    end
    return m
end

"""
    bisect!(mesh; onlyonce=false, maxlevel=0) -> mesh

Marked-element bisection refinement (geometry-aware) — the adaptive-refinement
path. Mark elements first with [`mark_for_refinement!`](@ref). Composes
`GetRefinement(GetGeometry(m))` → `Refinement::Bisect` with a `BisectionOptions`
whose `usemarkedelements` is enabled.

Optional `refine_p` / `refine_hp` forward to `BisectionOptions` for p-only or
hp marked bisection on a **new copied level** (via session helpers).
"""
function bisect!(m; onlyonce::Bool=false, maxlevel::Integer=0,
                 refine_p::Bool=false, refine_hp::Bool=false)
    opt = BisectionOptions()
    usemarkedelements!(opt, 1)
    onlyonce!(opt, onlyonce)
    maxlevel > 0 && maxlevel!(opt, Int(maxlevel))
    refine_p && refine_p!(opt, true)
    refine_hp && refine_hp!(opt, true)
    Bisect(GetRefinement(GetGeometry(m)), m, opt)
    return m
end

"""
    make_second_order!(mesh) -> mesh

Curve the mesh to second order (geometry-aware), via `Refinement::MakeSecondOrder`.
"""
function make_second_order!(m)
    MakeSecondOrder(GetRefinement(GetGeometry(m)), m)
    return m
end

# --- multigrid hierarchy (read via Ngx_Mesh: levels + parent maps) ----------
# Ngx_Mesh wraps the same shared_ptr<Mesh>; its parent maps are populated by
# Refine/Bisect and are exactly the data a geometric multigrid prolongation
# needs. Build one fresh after refining so it reflects the current hierarchy.

"""num_levels(mesh) -> number of refinement levels (`Ngx_Mesh::GetNLevels`)."""
num_levels(m) = GetNLevels(Ngx_Mesh(m))

"""level_nvertices(mesh, level) -> vertex count at `level` (0-based level index)."""
level_nvertices(m, level::Integer) = GetNVLevel(Ngx_Mesh(m), Int(level))

# Ngx_Mesh accessors are 0-based with -1 meaning "none" (the NGSolve convention).
# We normalize to the package's 1-based ids with 0 == none, so the parent maps
# index directly into `points`/`tetrahedra`.
_ngx_to_1based(v::Integer) = Int32(v) + Int32(1)

"""
    parent_nodes(mesh) -> 2×GetNP Matrix{Int32}

For each (1-based) vertex, its two coarse-level parent vertices (the endpoints of
the edge it bisects). A column of `(0, 0)` marks a vertex already present on the
coarser level. These ids index directly into [`points`](@ref) — the prolongation
stencil for nodal geometric multigrid.
"""
function parent_nodes(m)
    nm = Ngx_Mesh(m)
    np = GetNP(m)
    P = Matrix{Int32}(undef, 2, np)
    buf = zeros(Cint, 2)
    for i in 1:np
        GetParentNodes(nm, i - 1, buf)   # Ngx_Mesh query index is 0-based
        P[1, i] = _ngx_to_1based(buf[1]); P[2, i] = _ngx_to_1based(buf[2])
    end
    return P
end

"""
    parent_elements(mesh) -> Vector{Int32}

For each (1-based) volume element, its parent element on the coarser level (1-based;
`0` if none), via `Ngx_Mesh::GetParentElement`. Transfers element data across levels.
"""
function parent_elements(m)
    nm = Ngx_Mesh(m)
    ne = GetNE(m)
    return Int32[_ngx_to_1based(GetParentElement(nm, i - 1)) for i in 1:ne]
end

"""
    parent_surface_elements(mesh) -> Vector{Int32}

Per surface element, its parent on the coarser level (1-based; `0` if none), via
`Ngx_Mesh::GetParentSElement`.
"""
function parent_surface_elements(m)
    nm = Ngx_Mesh(m)
    nse = GetNSE(m)
    return Int32[_ngx_to_1based(GetParentSElement(nm, i - 1)) for i in 1:nse]
end

# --- mesh hierarchy (distinct mesh object per level) ------------------------

"""
    copy_mesh(mesh) -> mesh

A deep copy of `mesh` (points, elements, geometry), via `new_mesh` + the
`Mesh::operator=` binding. The copy carries no refinement history, so it is ready
to be refined into the next level of a hierarchy.
"""
function copy_mesh(src)
    m = new_mesh()
    assign(m, src)
    return m
end

"""
    MeshHierarchy

A growable stack of nested meshes `M₁ ⊂ M₂ ⊂ … ⊂ Mₙ` sharing one `geometry`.
Each level is a distinct mesh obtained by refining a *copy* of the previous
finest level, so a coarse vertex keeps its index in every finer level. That index
invariant is what makes the per-level parent maps ([`prolongation`](@ref) /
[`prolongation_operator`](@ref)) exact, which is what the geometric-multigrid
transfer operators are built from.

Build a coarse hierarchy with [`coarse_hierarchy`](@ref), then grow it *during*
the simulation with [`refine_uniform!`](@ref) (whole mesh) or
[`refine_marked!`](@ref) (error-driven, element-wise). Refinement is always
geometry-aware: new boundary vertices project onto the true CAD surface.
"""
struct MeshHierarchy
    geometry::Any
    meshes::Vector{Any}
end

Base.length(h::MeshHierarchy) = length(h.meshes)
Base.getindex(h::MeshHierarchy, k::Integer) = h.meshes[k]
Base.lastindex(h::MeshHierarchy) = length(h.meshes)
Base.iterate(h::MeshHierarchy, s=1) = s > length(h.meshes) ? nothing : (h.meshes[s], s + 1)

"""nlevels(h) -> number of mesh levels currently in the hierarchy."""
nlevels(h::MeshHierarchy) = length(h.meshes)
"""coarsest(h) / finest(h) -> the coarsest / finest mesh."""
coarsest(h::MeshHierarchy) = h.meshes[1]
finest(h::MeshHierarchy) = h.meshes[end]
"""geometry(h) -> the shared CAD geometry backing every level."""
geometry(h::MeshHierarchy) = h.geometry

"""
    coarse_hierarchy(geom; maxh) -> MeshHierarchy

Start a hierarchy with a single coarse mesh of `geom` (level 1). Solve on
`finest(h)`, then grow finer levels with [`refine_marked!`](@ref) /
[`refine_uniform!`](@ref) as the simulation proceeds.
"""
coarse_hierarchy(geom; maxh::Real) =
    MeshHierarchy(geom, Any[generate_mesh(geom; maxh=maxh)])

"""
    refine_uniform!(h) -> h

Append a new finest level: a uniformly refined copy of the current finest mesh
(`Refinement::Refine`). The new level's mapping is available as
`prolongation(h, nlevels(h))`.
"""
function refine_uniform!(h::MeshHierarchy)
    m = copy_mesh(finest(h))
    refine!(m)
    push!(h.meshes, m)
    return h
end

"""
    refine_marked!(h, marked) -> h

Append a new finest level by **element-wise, geometry-aware bisection** of a copy
of the current finest mesh — the adaptive-refinement step. `marked` is indexed
`1:GetNE(finest(h))` (a Bool vector / predicate from your error indicator);
marked elements are bisected (Netgen adds conforming closure refinement as
needed). The coarse→fine mapping is available as `prolongation(h, nlevels(h))`.
"""
function refine_marked!(h::MeshHierarchy, marked)
    m = copy_mesh(finest(h))
    UpdateTopology(m)
    mark_for_refinement!(m, marked)
    bisect!(m)
    push!(h.meshes, m)
    return h
end

"""
    uniform_hierarchy(geom; maxh, levels) -> MeshHierarchy

Convenience: a `levels`-deep hierarchy meshed at `maxh` (level 1) and uniformly
refined for each finer level, all built up front. Equivalent to
[`coarse_hierarchy`](@ref) followed by `levels-1` calls to
[`refine_uniform!`](@ref).
"""
function uniform_hierarchy(geom; maxh::Real, levels::Integer)
    levels >= 1 || throw(ArgumentError("levels must be ≥ 1 (got $levels)"))
    h = coarse_hierarchy(geom; maxh=maxh)
    for _ in 2:levels
        refine_uniform!(h)
    end
    return h
end

# --- per-level mapping (the data GMG transfer operators are built from) -----

"""
    prolongation(h, k) -> 2×GetNP(h[k]) Matrix{Int32}

The nodal parent map from level `k-1` to level `k`: for each vertex of `h[k]`, its
two parent vertices in `h[k-1]`, or `(0, 0)` for a vertex inherited unchanged.
`k` must be ≥ 2. This is the raw coarse→fine mapping; the actual transfer
operators are assembled from it elsewhere. Equivalent to `parent_nodes(h[k])`.
"""
function prolongation(h::MeshHierarchy, k::Integer)
    k >= 2 || throw(ArgumentError("prolongation is defined for levels k ≥ 2 (got $k)"))
    return parent_nodes(h.meshes[k])
end

# --- live session / snapshots / tags / hp / partition (consumer contract) ---
# Julia-only layers on top of the strict 1:1 bindings. See
# audit/NETGEN_LIVE_HIERARCHY_AND_PARTITION_CONTRACT_2026-07-01.md.
include("tags.jl")        # element extraction + region/tag helpers
include("hp.jl")          # hp-adaptivity readiness (order/hp-level readers)
include("fem.jl")         # curved maps, parent edge/face, periodic, codim names
include("session.jl")     # MeshHierarchySession + refinement requests
include("snapshots.jl")   # copied snapshot data contract for consumers
include("partition.jl")   # partition/load-balancing data contract
include("interop.jl")     # BREP string → NetgenGeometry bridge

# MESHING3_RESULT enum values (returned as Int by MeshVolume / OptimizeVolume)
const MESHING3_OK                  = 0
const MESHING3_GIVEUP              = 1
const MESHING3_NEGVOL              = 2
const MESHING3_OUTERSTEPSEXCEEDED  = 3
const MESHING3_TERMINATE           = 4
const MESHING3_BADSURFACEMESH      = 5

export load_step, load_iges, load_brep, load_geometry, generate_mesh,
       geometry2d, Circle, Rectangle, CSG2d,
       points, tetrahedra, surface_triangles,
       refine!, mark_for_refinement!, bisect!, make_second_order!,
       num_levels, level_nvertices, parent_nodes, parent_elements,
       parent_surface_elements,
       copy_mesh, MeshHierarchy, coarse_hierarchy, uniform_hierarchy,
       refine_uniform!, refine_marked!,
       nlevels, coarsest, finest, geometry, prolongation,
       # live session (authoritative handles + refinement requests)
       MeshHierarchySession, mesh_session, level_mesh, unsafe_level_mesh,
       mutate_level_mesh!, generation,
       request_uniform_refinement!, request_marked_refinement!,
       request_second_order!,
       request_set_element_orders!, request_set_element_order!,
       request_marked_p_refinement!, request_marked_hp_refinement!,
       request_hp_refine!, request_split_alfeld!,
       # snapshot data contract (copies for downstream consumers)
       MeshLevelSnapshot, HierarchyTransferSnapshot, MeshHierarchySnapshot,
       level_snapshot, transfer_snapshot, hierarchy_snapshot,
       supported_snapshot_topology, transfer_weight_semantics,
       # element extraction + region/tag helpers
       volume_tetrahedra, triangles2d, segments2d,
       cell_regions, boundary_regions, material_names, boundary_names,
       region_name_volume, region_name_surface, region_name_segment,
       # hp-adaptivity (read + apply)
       element_order, element_orders, element_orders_xyz,
       surface_element_order, surface_element_orders, hp_element_levels,
       set_element_order!, set_element_orders!, set_surface_element_order!,
       set_surface_element_orders!, mark_for_ngx_refinement!, ngx_refine!,
       hp_refine!, split_alfeld!,
       hp_clusters_available,
       cluster_rep_vertex, cluster_rep_edge, cluster_rep_face, cluster_rep_element,
       cluster_rep_vertices, cluster_rep_elements,
       # FEM geometry (curved maps, parent topology, periodic, codim names)
       volume_element_transformation, surface_element_transformation,
       domain_element_transformation, segment_element_transformation,
       volume_element_transformations,
       enable_topology_table!,
       has_parent_edges, parent_edges, parent_faces, face_edges,
       periodic_vertex_pairs, material_codim_name,
       find_element, mesh_h_at_point,
       # partitioning / load-balancing data contract
       native_partition_hint,
       occ_geometry_from_brep_string,
       NG_TET, NG_TRIG, NG_REFINE_H, NG_REFINE_P, NG_REFINE_HP,
       Segment, FaceDescriptor, LocalH, new_localh,
       STLParameters, STLGeometry, LoadSTL, load_stl,
       Box3d, Point3dTree, new_point3dtree,
       SplineGeometry2d, LoadSplineGeometry2d, load_splinegeometry2d,
       EdgeDescriptor,
       MeshVolume, OptimizeVolume, RemoveIllegalElements, ConformToFreeSegments,
       MESHING3_OK, MESHING3_GIVEUP, MESHING3_NEGVOL,
       MESHING3_OUTERSTEPSEXCEEDED, MESHING3_TERMINATE, MESHING3_BADSURFACEMESH

end # module Netgen
