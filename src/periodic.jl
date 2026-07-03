# --- periodic boundary condition setup (OCC face identification) -----------
# Julia helpers over Netgen.OCC_NrFaces/OCC_FaceBoundingBox/
# OCC_IdentifyFacesBulk/OCC_RebuildGeometry, which wrap Netgen's OCC-level
# Identifications mechanism (netgen::Identify + Identifications::ID_TYPE).
# OCC_IdentifyFacesBulk accepts several faces per side so netgen::Identify's
# own N*M IsMappedShape matching can pair up multiple fragments of a
# periodic face at once (e.g. after a boolean cut splits one outer face of
# an RVE unit cell into several pieces).
#
# Periodic identification must be set up on OCC faces *before* meshing:
# Netgen copies the "me" face's surface mesh through the given translation to
# build the "you" face's mesh, guaranteeing exact node correspondence (no
# interpolation error) — the correct mechanism for periodic boundary
# conditions in computational homogenization / RVE modeling.
#
# Caveat that shapes every function below: OCCGeometry snapshots its
# Identify()-registered pairs once, at construction time. Calling Identify()
# on an already-constructed geometry (which is the only way to reach faces
# by index from Julia) registers the pair in Netgen's global side table, but
# that geometry's own snapshot is now stale. The only safe fix — rebuilding
# the *same* OCCGeometry instance in place would duplicate its internal
# state — is to construct a *fresh* OCCGeometry from the same underlying
# shape (`Netgen.OCC_RebuildGeometry`), which re-discovers the identical
# faces (OCC's B-Rep sub-shapes are reference-counted, not recreated) with a
# now-current snapshot. `identify_periodic!`/`identify_periodic_box!` do this
# automatically and return the *new* handle — always use the returned
# geometry, not the one passed in.

"""
    occ_nr_faces(geom) -> Int

Number of OCC faces in `geom` (an OCC-backed `NetgenGeometry` from
`load_step`/`load_brep`/`load_iges`/`occ_geometry_from_brep_string`).
Throws `ArgumentError` if `geom` has no OCC face structure (e.g. an STL or 2D
geometry).
"""
function occ_nr_faces(geom)
    try
        return Int(Netgen.OCC_NrFaces(geom))
    catch e
        throw(ArgumentError("occ_nr_faces: $(sprint(showerror, e))"))
    end
end

"""
    occ_face_bbox(geom, facenr) -> (xmin, ymin, zmin, xmax, ymax, zmax)

Axis-aligned bounding box of OCC face `facenr` (1-based, `1:occ_nr_faces(geom)`)
in `geom`, as a `NamedTuple` (also destructures positionally). Throws
`ArgumentError` if `facenr` is out of range.
"""
function occ_face_bbox(geom, facenr::Integer)
    n = occ_nr_faces(geom)
    (1 <= facenr <= n) || throw(ArgumentError(
        "occ_face_bbox: face $facenr out of range (1:$n)"))
    buf = zeros(Cdouble, 6)
    Netgen.OCC_FaceBoundingBox(geom, Int(facenr), buf)
    return (xmin=buf[1], ymin=buf[2], zmin=buf[3], xmax=buf[4], ymax=buf[5], zmax=buf[6])
end

const _AXIS_INDEX = Dict(:x => 1, :y => 2, :z => 3)

_as_translation3(t::NTuple{3,<:Real}) = (Float64(t[1]), Float64(t[2]), Float64(t[3]))
_as_translation3(t::AbstractVector{<:Real}) = length(t) == 3 ?
    (Float64(t[1]), Float64(t[2]), Float64(t[3])) :
    throw(ArgumentError("translation must have length 3 (got $(length(t)))"))

"""
    faces_on_plane(geom, axis, value; atol=1e-6) -> Vector{Int}

1-based indices of OCC faces in `geom` whose bounding box is flat against the
plane `axis = value` (both bounding-box extrema along `axis` within `atol` of
`value`). `axis` is `:x`, `:y`, or `:z`.

Throws `ArgumentError` for `axis ∉ (:x, :y, :z)` or `atol <= 0`. `atol`
defaults to `1e-6` rather than something tighter because OCC's own bounding
box (`Bnd_Box`) carries a small built-in gap (observed ~1e-7 on a unit cube).
"""
function faces_on_plane(geom, axis::Symbol, value::Real; atol::Real=1e-6)
    haskey(_AXIS_INDEX, axis) || throw(ArgumentError(
        "faces_on_plane: axis must be :x, :y, or :z (got $axis)"))
    atol > 0 || throw(ArgumentError("faces_on_plane: atol must be > 0 (got $atol)"))
    k = _AXIS_INDEX[axis]
    n = occ_nr_faces(geom)
    result = Int[]
    for f in 1:n
        bbox = occ_face_bbox(geom, f)
        lo = (bbox.xmin, bbox.ymin, bbox.zmin)[k]
        hi = (bbox.xmax, bbox.ymax, bbox.zmax)[k]
        if abs(lo - value) <= atol && abs(hi - value) <= atol
            push!(result, f)
        end
    end
    return result
end

_as_facenr_vec(f::Integer) = Int[Int(f)]
_as_facenr_vec(f::AbstractVector{<:Integer}) = Int.(f)

"""
    identify_periodic!(geom, facenr_me, facenr_you, translation;
                        name="", type=NG_ID_PERIODIC) -> geom

Register a pre-mesh periodic identification between OCC faces `facenr_me`
and `facenr_you` of `geom` (1-based), mapped by the translation vector
`translation = (dx, dy, dz)`. Must be called before
[`generate_mesh`](@ref)/[`generate_mesh_result`](@ref); Netgen copies
`facenr_me`'s surface mesh through the translation to build `facenr_you`'s
mesh, guaranteeing exact node correspondence.

`facenr_me`/`facenr_you` may each be a single face index or a `Vector` of
several — pass vectors when a boolean cut has fragmented one periodic face
of a unit cell into multiple `TopoDS_Face` pieces (e.g. an inclusion/pore
touching the boundary). Netgen's own `Identify` does the fragment-to-fragment
matching internally (an N×M geometric check under `translation`), so the two
vectors don't need to be given in corresponding order.

Returns a **new** geometry handle — see this file's module note on why the
input `geom` must be discarded in favor of the return value. Verify the
result after meshing with [`periodic_vertex_pairs`](@ref).

**Use a distinct `name` for every identification you register** (e.g.
`"periodic_x"`, `"periodic_y"`, `"periodic_z"` for a 3-axis box): Netgen's
`Identifications::GetNr` maps identical names to the *same* identification
number, so reusing a name (including the default `""`) across multiple
calls silently collapses them into one `periodic_vertex_pairs` group instead
of keeping them separately retrievable.

Throws `ArgumentError` if any face index is out of range, either list is
empty, or Netgen matched fewer sub-shape pairs than `min(length(facenr_me),
length(facenr_you))` — a partial match means at least one fragment was left
un-periodicized, which is a silent correctness risk, not something to warn
about and continue.
"""
function identify_periodic!(geom, facenr_me::Union{Integer,AbstractVector{<:Integer}},
                             facenr_you::Union{Integer,AbstractVector{<:Integer}},
                             translation;
                             name::AbstractString="", type::Integer=NG_ID_PERIODIC)
    n = occ_nr_faces(geom)
    me = _as_facenr_vec(facenr_me)
    you = _as_facenr_vec(facenr_you)
    isempty(me) && throw(ArgumentError("identify_periodic!: facenr_me is empty"))
    isempty(you) && throw(ArgumentError("identify_periodic!: facenr_you is empty"))
    for f in me
        (1 <= f <= n) || throw(ArgumentError(
            "identify_periodic!: facenr_me=$f out of range (1:$n)"))
    end
    for f in you
        (1 <= f <= n) || throw(ArgumentError(
            "identify_periodic!: facenr_you=$f out of range (1:$n)"))
    end
    tx, ty, tz = _as_translation3(translation)
    nident = Int(Netgen.OCC_IdentifyFacesBulk(geom, Cint.(me), Cint.(you),
                                               String(name), Int(type), tx, ty, tz))
    expected = min(length(me), length(you))
    nident == expected || throw(ArgumentError(
        "identify_periodic!: matched $nident of $expected expected sub-shape " *
        "pair(s) between faces $me and $you under translation $translation " *
        "(wrong face pair(s), translation, or a genuinely unmatched fragment)"))
    return Netgen.OCC_RebuildGeometry(geom)
end

"""
    identify_periodic_box!(geom, axis; atol=1e-6, name="", type=NG_ID_PERIODIC) -> geom

Convenience for an axis-aligned box/hex unit cell: find the min- and
max-face along `axis` (via [`faces_on_plane`](@ref) at `geom`'s own
bounding-box extrema) and call [`identify_periodic!`](@ref) with the
translation inferred from the extent along `axis`.

Returns a **new** geometry handle, exactly as [`identify_periodic!`](@ref)
does — discard the input `geom`, use the return value.

Each extreme may consist of several `TopoDS_Face` fragments (e.g. a boolean
cut for an inclusion/pore that touches the periodic boundary splits the
plain box face into pieces) — all faces found at each extreme are passed
straight to [`identify_periodic!`](@ref), which relies on Netgen's own
fragment-to-fragment matching. Throws `ArgumentError` if either extreme has
no face at all, or if the match count comes up short (a genuinely unmatched
fragment — see [`identify_periodic!`](@ref)); in that case fall back to
explicit [`identify_periodic!`](@ref) calls with known face indices.
"""
function identify_periodic_box!(geom, axis::Symbol; atol::Real=1e-6,
                                 name::AbstractString="", type::Integer=NG_ID_PERIODIC)
    haskey(_AXIS_INDEX, axis) || throw(ArgumentError(
        "identify_periodic_box!: axis must be :x, :y, or :z (got $axis)"))
    k = _AXIS_INDEX[axis]
    n = occ_nr_faces(geom)
    los = Float64[]; his = Float64[]
    for f in 1:n
        bbox = occ_face_bbox(geom, f)
        push!(los, (bbox.xmin, bbox.ymin, bbox.zmin)[k])
        push!(his, (bbox.xmax, bbox.ymax, bbox.zmax)[k])
    end
    vmin, vmax = minimum(los), maximum(his)
    vmin < vmax || throw(ArgumentError(
        "identify_periodic_box!: zero extent along axis $axis"))
    faces_lo = faces_on_plane(geom, axis, vmin; atol=atol)
    faces_hi = faces_on_plane(geom, axis, vmax; atol=atol)
    (isempty(faces_lo) || isempty(faces_hi)) && throw(ArgumentError(
        "identify_periodic_box!: found no face at an extreme of axis $axis " *
        "($(length(faces_lo)) at $vmin, $(length(faces_hi)) at $vmax)"))
    # OCC's own bounding box carries a small built-in tolerance gap (observed
    # ~1e-7, matching Precision::Confusion()), so the raw vmax-vmin extent is
    # not exact enough for Identify()'s own (tighter, non-configurable)
    # matching tolerance. Round to atol's own decimal scale to remove it —
    # exact for the common case (a box built at round coordinates); if your
    # geometry genuinely has a non-round extent finer than atol, compute the
    # translation yourself and call identify_periodic! directly instead.
    digits = max(0, round(Int, -log10(atol)))
    extent = round(vmax - vmin; digits=digits)
    translation = ntuple(i -> i == k ? extent : 0.0, 3)
    return identify_periodic!(geom, faces_lo, faces_hi, translation; name=name, type=type)
end
