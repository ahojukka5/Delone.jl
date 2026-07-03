# --- Delone <-> Gmsh package extension ---------------------------------------
# Loaded automatically (Base.get_extension) when the host session has both
# Delone and Gmsh loaded. See Project.toml [weakdeps]/[extensions].
# Requires Julia >= 1.9.
#
# Gmsh needs no hand-written CxxWrap binding layer the way Netgen does:
# `gmsh_jll` ships a complete, official, auto-generated Julia API
# (`gmsh_jll.gmsh_api`, produced by Gmsh's own build from its language-neutral
# API spec), and the registered `Gmsh` package wraps it safely
# (`include(gmsh_jll.gmsh_api)` + idempotent `initialize`/`finalize`). This
# extension is Julian composition on top of that, following the same pattern
# already used by this ecosystem's `Oodi.jl`/`JuliaFEM.jl` Gmsh extensions.
#
# Session model: per-call `Gmsh.initialize()`/`Gmsh.finalize()`, not a
# persistent session -- v1's scope (one file in, one snapshot out) never has
# two live models needing to coexist. `Gmsh.initialize()` returns `true` only
# if *it* performed initialization (idempotent otherwise), so `finalize()` is
# only called when this function was the one that opened Gmsh -- unlike a
# naive try/finally, this doesn't tear down a Gmsh session the caller's own
# code already had open for something else.
#
# Node/element "tags" from Gmsh are not guaranteed dense/contiguous by the
# API (usually are, for a freshly generated mesh, but that's a convention,
# not a guarantee) -- an explicit tag->index Dict is always built, never
# assumed.
module DeloneGmshExt

using Delone
using Delone: MeshLevelSnapshot, GmshPeriodicGroup, GmshMeshGenerationResult
import Gmsh
import Gmsh: gmsh

# Gmsh element type ids (from the Gmsh API docs / gmsh.model.mesh.getElementProperties).
const _GMSH_TET4 = 4
const _GMSH_TRI3 = 2

# Deliberately not reusing Delone's own (private) _AXIS_INDEX from
# src/periodic.jl -- kept self-contained rather than reaching across the
# package boundary for 3 lines of lookup table.
const _AXIS_INDEX = Dict(:x => 1, :y => 2, :z => 3)

# Shared by generate_gmsh_mesh and gmsh_geometry_info: open a fresh model
# and import path into it (caller is responsible for the init/finally
# bracket around this, since geometry_info doesn't mesh afterward).
function _import_model(path::AbstractString, who::String)
    isfile(path) || throw(ArgumentError("$who: file not found: $path"))
    gmsh.option.setNumber("General.Terminal", 0)
    gmsh.model.add("delone")
    try
        gmsh.model.occ.importShapes(String(path))
    catch e
        e isa ErrorException || rethrow()
        throw(ArgumentError("$who: failed to import $path: $(e.msg)"))
    end
    gmsh.model.occ.synchronize()
    return nothing
end

# (tag, xmin, ymin, zmin, xmax, ymax, zmax) named tuples for every OCC
# entity of dimension `dim` in the current (already-synchronized) model.
function _entity_bboxes(dim::Integer)
    result = NamedTuple[]
    for (_, tag) in gmsh.model.occ.getEntities(dim)
        xmin, ymin, zmin, xmax, ymax, zmax = gmsh.model.occ.getBoundingBox(dim, tag)
        push!(result, (tag=tag, xmin=xmin, ymin=ymin, zmin=zmin, xmax=xmax, ymax=ymax, zmax=zmax))
    end
    return result
end

function Delone.gmsh_geometry_info(path::AbstractString)
    did_init = Gmsh.initialize()
    try
        _import_model(path, "gmsh_geometry_info")
        faces = _entity_bboxes(2)
        solids = _entity_bboxes(3)
        xmin, ymin, zmin, xmax, ymax, zmax = gmsh.model.getBoundingBox(-1, -1)
        return (faces=faces, solids=solids,
                bounding_box=(xmin=xmin, ymin=ymin, zmin=zmin, xmax=xmax, ymax=ymax, zmax=zmax))
    finally
        did_init && Gmsh.finalize()
    end
end

# Validate a `regions`/`boundary_names` dict entry: values may be a single
# tag or a vector of tags, every tag must be a real dim-`dim` entity, and no
# tag may be claimed by two different names (a flat cell_regions vector
# can't represent multi-membership, so this is a hard error, not a
# last-writer-wins fallback). Returns [(tags, name), ...] in dict order.
function _validate_named_tag_dict(dict, dim::Integer, kwname::String, valid_tags)
    groups = Tuple{Vector{Int},String}[]
    seen = Dict{Int,String}()
    for (name, v) in dict
        tags = v isa Integer ? Int[v] : Int.(collect(v))
        isempty(tags) && throw(ArgumentError("$kwname: entry \"$name\" has no tags"))
        for t in tags
            t in valid_tags || throw(ArgumentError(
                "$kwname: tag $t (entry \"$name\") is not a valid dim=$dim entity tag"))
            haskey(seen, t) && throw(ArgumentError(
                "$kwname: tag $t is claimed by both \"$(seen[t])\" and \"$name\" -- " *
                "each entity may belong to only one named region"))
            seen[t] = name
        end
        push!(groups, (tags, String(name)))
    end
    return groups
end

# Register physical groups for already-validated (tags, name) groups;
# returns [(tags, name, physical_tag), ...] for later use at extraction time.
function _register_physical_groups(dim::Integer, groups)
    return [(tags, name, gmsh.model.addPhysicalGroup(dim, tags, -1, name))
            for (tags, name) in groups]
end

# Per-element region id lookup for extraction: `elem_tags_flat` is the flat
# list of element tags already extracted for dimension `dim` (in the same
# order `cell_regions`/`boundary_regions` must be built in). Falls back to
# `default` for elements not covered by any declared group -- and skips all
# of this (returning a plain fill, matching pre-tagging behavior exactly)
# when no groups were declared.
function _region_ids_for(dim::Integer, groups, elem_tags_flat::Vector{<:Integer}, default::Int32)
    isempty(groups) && return fill(default, length(elem_tags_flat))
    tag_to_region = Dict{Int,Int32}()
    for (tags, _, ptag) in groups
        for etag in tags
            _, ge_tags, _ = gmsh.model.mesh.getElements(dim, etag)
            for arr in ge_tags, t in arr
                tag_to_region[t] = Int32(ptag)
            end
        end
    end
    return Int32[get(tag_to_region, t, default) for t in elem_tags_flat]
end

_names_dict(groups) = Dict{Int32,String}(Int32(ptag) => name for (_, name, ptag) in groups)

# Normalize one `refine_near` entry (a named tuple with exactly one of
# faces=/curves=/point= plus hmin=/hmax=/distmin=/distmax=) to
# (kind, target, hmin, hmax, distmin, distmax); throw ArgumentError on
# malformed input. Mirrors MeshOptions._normalize_local_size_entry's style.
function _normalize_refine_near_entry(entry)
    entry isa NamedTuple || throw(ArgumentError(
        "refine_near entries must be named tuples with faces=/curves=/point=, " *
        "hmin=, hmax=, distmin=, distmax= (got $(typeof(entry)))"))
    faces = get(entry, :faces, nothing)
    curves = get(entry, :curves, nothing)
    point = get(entry, :point, nothing)
    count(!isnothing, (faces, curves, point)) == 1 || throw(ArgumentError(
        "refine_near entry must specify exactly one of faces=, curves=, or point="))
    hmin = get(entry, :hmin, nothing)
    hmax = get(entry, :hmax, nothing)
    distmin = get(entry, :distmin, nothing)
    distmax = get(entry, :distmax, nothing)
    (hmin === nothing || hmax === nothing || distmin === nothing || distmax === nothing) &&
        throw(ArgumentError("refine_near entry is missing hmin=/hmax=/distmin=/distmax="))
    hmin > 0 || throw(ArgumentError("refine_near: hmin must be > 0 (got $hmin)"))
    hmax >= hmin || throw(ArgumentError(
        "refine_near: hmax must be >= hmin (got hmax=$hmax, hmin=$hmin)"))
    distmin >= 0 || throw(ArgumentError("refine_near: distmin must be >= 0 (got $distmin)"))
    distmax > distmin || throw(ArgumentError(
        "refine_near: distmax must be > distmin (got distmax=$distmax, distmin=$distmin)"))
    args = (Float64(hmin), Float64(hmax), Float64(distmin), Float64(distmax))
    faces !== nothing && return (:faces, faces isa Integer ? Int[faces] : Int.(collect(faces)), args...)
    curves !== nothing && return (:curves, curves isa Integer ? Int[curves] : Int.(collect(curves)), args...)
    length(point) == 3 || throw(ArgumentError(
        "refine_near: point must have length 3 (got $(length(point)))"))
    return (:point, Float64.(collect(point)), args...)
end

# Builds Distance+Threshold fields per entry, combines multiple zones via a
# Min field, and sets the result as the background mesh size field. No-op
# (today's exact maxh-only behavior) when `entries` is empty.
function _apply_refine_near!(entries)
    isempty(entries) && return nothing
    threshold_tags = Float64[]
    for (kind, target, hmin, hmax, distmin, distmax) in entries
        dtag = gmsh.model.mesh.field.add("Distance")
        if kind === :faces
            gmsh.model.mesh.field.setNumbers(dtag, "SurfacesList", Float64.(target))
        elseif kind === :curves
            gmsh.model.mesh.field.setNumbers(dtag, "CurvesList", Float64.(target))
        else
            ptag = gmsh.model.occ.addPoint(target[1], target[2], target[3])
            gmsh.model.occ.synchronize()
            gmsh.model.mesh.field.setNumbers(dtag, "PointsList", Float64[ptag])
        end
        ttag = gmsh.model.mesh.field.add("Threshold")
        gmsh.model.mesh.field.setNumber(ttag, "InField", dtag)
        gmsh.model.mesh.field.setNumber(ttag, "SizeMin", hmin)
        gmsh.model.mesh.field.setNumber(ttag, "SizeMax", hmax)
        gmsh.model.mesh.field.setNumber(ttag, "DistMin", distmin)
        gmsh.model.mesh.field.setNumber(ttag, "DistMax", distmax)
        push!(threshold_tags, Float64(ttag))
    end
    bgtag = if length(threshold_tags) == 1
        Int(threshold_tags[1])
    else
        mtag = gmsh.model.mesh.field.add("Min")
        gmsh.model.mesh.field.setNumbers(mtag, "FieldsList", threshold_tags)
        mtag
    end
    gmsh.model.mesh.field.setAsBackgroundMesh(bgtag)
    # Field-only sizing: prevent boundary/point/curvature-based sizing from
    # overriding the field (see Gmsh's own t10.jl tutorial for this idiom).
    gmsh.option.setNumber("Mesh.MeshSizeExtendFromBoundary", 0)
    gmsh.option.setNumber("Mesh.MeshSizeFromPoints", 0)
    gmsh.option.setNumber("Mesh.MeshSizeFromCurvature", 0)
    return nothing
end

_affine_translation(t::NTuple{3,Float64}) =
    Float64[1, 0, 0, t[1], 0, 1, 0, t[2], 0, 0, 1, t[3], 0, 0, 0, 1]

# Normalize one `periodic` entry (lo=, hi=, translation=, name=nothing) to
# (lo_tags, hi_tags, translation, name). Unlike Netgen's identify_periodic!,
# Gmsh's setPeriodic pairs lo/hi *by position*, not by geometric matching --
# so lo and hi must already have the same length, in corresponding order.
function _normalize_periodic_entry(entry)
    entry isa NamedTuple || throw(ArgumentError(
        "periodic entries must be named tuples with lo=, hi=, translation=, " *
        "name=nothing (got $(typeof(entry)))"))
    lo = get(entry, :lo, nothing)
    hi = get(entry, :hi, nothing)
    translation = get(entry, :translation, nothing)
    name = get(entry, :name, nothing)
    (lo === nothing || hi === nothing || translation === nothing) && throw(ArgumentError(
        "periodic entry is missing lo=/hi=/translation="))
    lo_tags = lo isa Integer ? Int[lo] : Int.(collect(lo))
    hi_tags = hi isa Integer ? Int[hi] : Int.(collect(hi))
    isempty(lo_tags) && throw(ArgumentError("periodic entry: lo= has no tags"))
    length(lo_tags) == length(hi_tags) || throw(ArgumentError(
        "periodic entry: lo= and hi= must have the same length (Gmsh pairs them " *
        "by position, got $(length(lo_tags)) lo vs $(length(hi_tags)) hi)"))
    length(translation) == 3 || throw(ArgumentError(
        "periodic translation must have length 3 (got $(length(translation)))"))
    return (lo_tags, hi_tags, NTuple{3,Float64}(Float64.(collect(translation))),
            name === nothing ? nothing : String(name))
end

# periodic_box's axis-aligned convenience: mirrors identify_periodic_box!'s
# extreme-face-finding algorithm, but only accepts exactly one face per
# extreme -- Gmsh's setPeriodic has no fragment-matching to safely
# disambiguate several fragments the way Netgen's netgen::Identify does.
function _periodic_box_entry_for_axis(axis::Symbol, atol::Real, faces)
    haskey(_AXIS_INDEX, axis) || throw(ArgumentError(
        "periodic_box: axis must be :x, :y, or :z (got $axis)"))
    isempty(faces) && throw(ArgumentError("periodic_box: geometry has no faces"))
    k = _AXIS_INDEX[axis]
    los = [(f.xmin, f.ymin, f.zmin)[k] for f in faces]
    his = [(f.xmax, f.ymax, f.zmax)[k] for f in faces]
    vmin, vmax = minimum(los), maximum(his)
    vmin < vmax || throw(ArgumentError("periodic_box: zero extent along axis $axis"))
    faces_lo = faces_on_plane(faces, axis, vmin; atol=atol)
    faces_hi = faces_on_plane(faces, axis, vmax; atol=atol)
    (length(faces_lo) == 1 && length(faces_hi) == 1) || throw(ArgumentError(
        "periodic_box: expected exactly one face at each extreme of axis $axis, " *
        "found $(length(faces_lo)) at $vmin and $(length(faces_hi)) at $vmax -- " *
        "ambiguous for Gmsh's position-paired setPeriodic; use periodic= with " *
        "explicit, manually-ordered face tags"))
    digits = max(0, round(Int, -log10(atol)))
    extent = round(vmax - vmin; digits=digits)
    translation = ntuple(i -> i == k ? extent : 0.0, 3)
    return (faces_lo, faces_hi, NTuple{3,Float64}(translation), "periodic_$axis")
end

# Calls setPeriodic for every already-validated entry; returns the same
# entries (for later vertex_pairs extraction in _extract_snapshot).
function _apply_periodic!(entries, face_tags)
    for (lo, hi, translation, _) in entries
        all(t -> t in face_tags, lo) || throw(ArgumentError(
            "periodic: lo face tag(s) $(setdiff(lo, face_tags)) not found in this geometry"))
        all(t -> t in face_tags, hi) || throw(ArgumentError(
            "periodic: hi face tag(s) $(setdiff(hi, face_tags)) not found in this geometry"))
        gmsh.model.mesh.setPeriodic(2, hi, lo, _affine_translation(translation))
    end
    return entries
end

function Delone.generate_gmsh_mesh(path::AbstractString; maxh::Union{Nothing,Real}=nothing,
                                    regions::AbstractDict=Dict{String,Any}(),
                                    boundary_names::AbstractDict=Dict{String,Any}(),
                                    refine_near::AbstractVector=[],
                                    periodic::AbstractVector=[],
                                    periodic_box::Union{Nothing,Symbol,AbstractVector{Symbol}}=nothing,
                                    result::Bool=false)
    did_init = Gmsh.initialize()
    try
        _import_model(path, "generate_gmsh_mesh")
        solid_tags = [tag for (_, tag) in gmsh.model.occ.getEntities(3)]
        face_tags = [tag for (_, tag) in gmsh.model.occ.getEntities(2)]
        region_groups = _validate_named_tag_dict(regions, 3, "regions", solid_tags)
        boundary_groups = _validate_named_tag_dict(boundary_names, 2, "boundary_names", face_tags)
        volume_groups = _register_physical_groups(3, region_groups)
        surface_groups = _register_physical_groups(2, boundary_groups)
        curve_tags = [tag for (_, tag) in gmsh.model.occ.getEntities(1)]
        refine_entries = _normalize_refine_near_entry.(refine_near)
        for (kind, target, _, _, _, _) in refine_entries
            kind === :point && continue
            valid = kind === :faces ? face_tags : curve_tags
            all(t -> t in valid, target) || throw(ArgumentError(
                "refine_near: $(kind === :faces ? "face" : "curve") tag(s) " *
                "$(setdiff(target, valid)) not found in this geometry"))
        end
        _apply_refine_near!(refine_entries)
        periodic_entries = _normalize_periodic_entry.(periodic)
        if periodic_box !== nothing
            axes = periodic_box isa Symbol ? [periodic_box] : collect(periodic_box)
            faces = _entity_bboxes(2)
            periodic_entries = vcat(periodic_entries,
                [_periodic_box_entry_for_axis(axis, 1e-6, faces) for axis in axes])
        end
        _apply_periodic!(periodic_entries, face_tags)
        maxh !== nothing && gmsh.option.setNumber("Mesh.MeshSizeMax", Float64(maxh))
        try
            gmsh.model.mesh.generate(3)
        catch e
            e isa ErrorException || rethrow()
            throw(ArgumentError("generate_gmsh_mesh: meshing failed: $(e.msg)"))
        end
        snapshot, periodic_groups = _extract_snapshot(volume_groups, surface_groups, periodic_entries)
        return result ? GmshMeshGenerationResult(snapshot, periodic_groups) : snapshot
    finally
        did_init && Gmsh.finalize()
    end
end

function Delone.gmsh_mesh_from_brep_string(brep::AbstractString; kwargs...)
    path = tempname() * ".brep"
    try
        write(path, brep)
        return Delone.generate_gmsh_mesh(path; kwargs...)
    finally
        isfile(path) && rm(path; force=true)
    end
end

function _extract_snapshot(volume_groups=Tuple{Vector{Int},String,Int}[],
                            surface_groups=Tuple{Vector{Int},String,Int}[],
                            periodic_entries=Tuple{Vector{Int},Vector{Int},NTuple{3,Float64},Union{Nothing,String}}[])
    node_tags, coord, _ = gmsh.model.mesh.getNodes()
    n = length(node_tags)
    n > 0 || throw(ArgumentError("generate_gmsh_mesh: mesh has zero nodes"))
    tag_to_idx = Dict(t => Int32(i) for (i, t) in enumerate(node_tags))
    coords = Matrix{Float64}(undef, 3, n)
    @inbounds for i in 1:n
        coords[:, i] = @view coord[3i-2:3i]
    end

    elem_types, elem_tags, elem_node_tags = gmsh.model.mesh.getElements(3, -1)
    isempty(elem_tags) && throw(ArgumentError("generate_gmsh_mesh: mesh has zero tetrahedra"))
    length(elem_types) == 1 && elem_types[1] == _GMSH_TET4 || throw(ArgumentError(
        "generate_gmsh_mesh: expected a pure Tet4 volume mesh (Gmsh element " *
        "type $_GMSH_TET4), got types $elem_types -- mixed/non-tet meshes are " *
        "not yet supported by MeshLevelSnapshot"))
    ne = length(elem_tags[1])
    vol = reshape(Int32[tag_to_idx[t] for t in elem_node_tags[1]], 4, ne)
    cell_regions = _region_ids_for(3, volume_groups, elem_tags[1], Int32(1))

    btypes, btags, bnode_tags = gmsh.model.mesh.getElements(2, -1)
    surf, boundary_regions = if isempty(btags)
        Matrix{Int32}(undef, 3, 0), Int32[]
    else
        length(btypes) == 1 && btypes[1] == _GMSH_TRI3 || throw(ArgumentError(
            "generate_gmsh_mesh: expected pure Tri3 boundary facets (Gmsh " *
            "element type $_GMSH_TRI3), got types $btypes"))
        reshape(Int32[tag_to_idx[t] for t in bnode_tags[1]], 3, length(btags[1])),
        _region_ids_for(2, surface_groups, btags[1], Int32(0))
    end

    # Node-index-space periodic groups (using tag_to_idx's un-compacted
    # numbering) built before _drop_unreferenced_nodes, then remapped
    # through the same compaction below -- periodic slave/master nodes are
    # always real (referenced) nodes, but their *index* can still shift if
    # an unreferenced node earlier in Gmsh's own tag ordering gets dropped.
    periodic_groups = GmshPeriodicGroup[]
    for (lo, hi, translation, name) in periodic_entries
        pairs = Tuple{Int32,Int32}[]
        for htag in hi
            _, slave_node_tags, master_node_tags, _ = gmsh.model.mesh.getPeriodicNodes(2, htag)
            for (nt, ntm) in zip(slave_node_tags, master_node_tags)
                # (master_idx, slave_idx), matching periodic_vertex_pairs's
                # (lo_idx, hi_idx) convention: X[:, j] - X[:, i] == translation.
                push!(pairs, (tag_to_idx[ntm], tag_to_idx[nt]))
            end
        end
        push!(periodic_groups, GmshPeriodicGroup(name, lo, hi, translation, pairs))
    end

    coords, vol, surf, remap = _drop_unreferenced_nodes(coords, vol, surf)
    periodic_groups = [
        GmshPeriodicGroup(g.name, g.master_tags, g.slave_tags, g.translation,
                           [(remap[i], remap[j]) for (i, j) in g.vertex_pairs])
        for g in periodic_groups]

    snapshot = MeshLevelSnapshot{3,Float64,Int32}(
        coords, vol, surf,
        cell_regions, boundary_regions,
        _names_dict(volume_groups), _names_dict(surface_groups),
        :tet, :tri, 1, 0)
    return snapshot, periodic_groups
end

# A `refine_near` point= entry adds a free-standing OCC point purely to
# anchor a Distance field; Gmsh meshes it as a genuine 0-D mesh point that
# ends up in getNodes()'s global list but is referenced by zero tets/tris --
# a real invariant break for downstream consumers (VTK export, FEM assembly
# expecting every node to be used). Compact coords/connectivity to drop any
# such orphans; a no-op fast path when everything is already referenced
# (the overwhelmingly common case, and today's exact behavior otherwise).
# The 4th return value is the (possibly identity) old-index -> new-index
# remap, needed to keep periodic vertex_pairs consistent.
function _drop_unreferenced_nodes(coords::Matrix{Float64}, vol::Matrix{Int32}, surf::Matrix{Int32})
    n = size(coords, 2)
    referenced = falses(n)
    @inbounds for j in 1:size(vol, 2), i in 1:size(vol, 1)
        referenced[vol[i, j]] = true
    end
    @inbounds for j in 1:size(surf, 2), i in 1:size(surf, 1)
        referenced[surf[i, j]] = true
    end
    all(referenced) && return coords, vol, surf, Int32.(1:n)
    keep = findall(referenced)
    remap = zeros(Int32, n)
    remap[keep] = Int32.(1:length(keep))
    return coords[:, keep], remap[vol], remap[surf], remap
end

end # module
