using Netgen
using Test

# OpenCascade.jl is a test dependency (`Pkg.test()`). When running this file
# directly in the monorepo, add the sibling package if needed.
const _OC_PATH = normpath(@__DIR__, "..", "..", "OpenCascade.jl")
if Base.find_package("OpenCascade") === nothing && isdir(_OC_PATH)
    import Pkg
    Pkg.develop(Pkg.PackageSpec(path=_OC_PATH))
end
using OpenCascade

const STEP     = joinpath(@__DIR__, "fixtures", "frame.step")
const CYLINDER = joinpath(@__DIR__, "fixtures", "cylinder.brep")  # unit cylinder, r=1, h=2

@testset "Netgen.jl (CxxWrap, strict 1:1 names)" begin
    # Netgen mesh core
    include("mesh.jl")
    include("refinement.jl")
    include("hierarchy.jl")
    include("session.jl")
    include("tags_hp.jl")
    include("hp_apply.jl")
    include("fem.jl")
    include("brep_bridge.jl")
    include("geom2d.jl")
    include("extras.jl")
    include("stl.jl")
    include("gprim.jl")
    include("mesh2.jl")
    include("ngx2.jl")
end
