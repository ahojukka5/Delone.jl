# --- Gmsh backend stub (real implementation in ext/DeloneGmshExt.jl) --------
# Gmsh needs no hand-written CxxWrap binding layer the way Netgen does:
# `gmsh_jll` ships a complete, official, auto-generated Julia API
# (`gmsh_jll.gmsh_api`), wrapped safely by the registered `Gmsh` package
# (`include(gmsh_jll.gmsh_api)` + idempotent `initialize`/`finalize`). This
# stub exists only because Julia package extensions can add *methods* to an
# existing function binding, not introduce a new top-level name from scratch
# (same reason `export_vtu` has a stub in `src/export_mesh.jl`).

"""
    generate_gmsh_mesh(path; maxh=nothing) -> MeshLevelSnapshot{3,Float64,Int32}

Mesh a STEP/IGES/BREP file via Gmsh's OpenCASCADE-based CAD kernel and volume
mesher. Defined by the `DeloneGmshExt` package extension and only becomes
usable once `Gmsh` is loaded (`using Gmsh`) — see [`generate_mesh`](@ref) for
the always-available Netgen backend.
"""
function generate_gmsh_mesh(args...; kwargs...)
    throw(ArgumentError(
        "generate_gmsh_mesh requires Gmsh to be loaded (`using Gmsh`) to activate " *
        "the DeloneGmshExt package extension; see generate_mesh for the " *
        "always-available Netgen backend"))
end
