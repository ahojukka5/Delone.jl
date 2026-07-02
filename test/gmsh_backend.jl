# DeloneGmshExt: only exercised when Gmsh is actually installed in this
# environment (the extension itself only needs the `Gmsh` weakdep to be
# *defined* -- see Project.toml [weakdeps]/[extensions] -- precompiling and
# loading `Delone` never requires Gmsh to be present). The main test suite
# must not gain a hard dependency on Gmsh just to keep this file green, so
# everything below is guarded exactly like `test/writevtk_ext.jl`.
@testset "DeloneGmshExt (Gmsh backend)" begin
    if Base.find_package("Gmsh") === nothing
        @info "Gmsh not installed; skipping DeloneGmshExt verification " *
              "(generate_gmsh_mesh still exists as a stub that throws a clear " *
              "error pointing at generate_mesh/Gmsh without it)"
        @test_throws ArgumentError generate_gmsh_mesh("dummy.step")
    else
        @eval using Gmsh

        @test Base.get_extension(Delone, :DeloneGmshExt) !== nothing

        s = generate_gmsh_mesh(STEP; maxh=60.0)
        @test s isa MeshLevelSnapshot{3,Float64,Int32}
        @test size(s.coordinates, 2) > 0
        @test size(s.volume_connectivity, 2) > 0
        @test size(s.surface_connectivity, 2) > 0

        # regression check on the tag->index remap logic
        @test all(1 .<= s.volume_connectivity .<= size(s.coordinates, 2))
        @test all(1 .<= s.surface_connectivity .<= size(s.coordinates, 2))

        # cross-backend correctness: same real-world geometry, not bit-identical
        # meshing -- Netgen and Gmsh triangulate the same OCC curved boundary
        # independently, so this checks bounding boxes agree, not exact equality.
        geom = load_geometry(STEP)
        m = generate_mesh(geom; maxh=60.0)
        bbox_n = mesh_bounding_box(m)
        lo_g = vec(minimum(s.coordinates, dims=2))
        hi_g = vec(maximum(s.coordinates, dims=2))
        @test isapprox(collect(bbox_n.min), lo_g; atol=1.0)
        @test isapprox(collect(bbox_n.max), hi_g; atol=1.0)

        @test_throws ArgumentError generate_gmsh_mesh("does_not_exist.step")
        @test_throws ArgumentError generate_gmsh_mesh(joinpath(@__DIR__, "fixtures", "tet.stl"))

        # Netgen/Gmsh OCCT coexistence smoke test, both call orders -- the one
        # risk this integration cannot resolve by static review (see ROADMAP.md
        # Workstream F2): both backends link OpenCASCADE via a shared OCCT_jll
        # resolution, but whether OCCT's own process-wide state tolerates being
        # driven by two independent C++ call chains interleaved in one process
        # is an empirical question, not a documentation one.
        geom_a = load_geometry(STEP)
        m_a = generate_mesh(geom_a; maxh=60.0)
        s_a = generate_gmsh_mesh(STEP; maxh=60.0)
        @test num_nodes(m_a) > 0
        @test size(s_a.coordinates, 2) > 0

        s_b = generate_gmsh_mesh(STEP; maxh=60.0)
        geom_b = load_geometry(STEP)
        m_b = generate_mesh(geom_b; maxh=60.0)
        @test size(s_b.coordinates, 2) > 0
        @test num_nodes(m_b) > 0

        # BREP-string bridge (Monge -> Gmsh), the Gmsh-backend analogue of
        # occ_geometry_from_brep_string's bridge for Netgen.
        brep = to_brep_string(box(1.0, 1.0, 1.0))
        sb = gmsh_mesh_from_brep_string(brep; maxh=0.3)
        @test sb isa MeshLevelSnapshot{3,Float64,Int32}
        @test size(sb.coordinates, 2) > 0
        @test isapprox(vec(minimum(sb.coordinates, dims=2)), [0.0, 0.0, 0.0]; atol=1e-8)
        @test isapprox(vec(maximum(sb.coordinates, dims=2)), [1.0, 1.0, 1.0]; atol=1e-8)
        @test_throws ArgumentError gmsh_mesh_from_brep_string("not a real brep")

        # generate_mesh(...; backend=:gmsh) selector
        s_sel = generate_mesh(STEP; maxh=60.0, backend=:gmsh)
        @test s_sel isa MeshLevelSnapshot{3,Float64,Int32}
        @test size(s_sel.coordinates, 2) > 0
        @test_throws ArgumentError generate_mesh(STEP; maxh=60.0, backend=:gmsh, result=true)
        @test_throws ArgumentError generate_mesh(
            STEP; options=MeshOptions(maxh=60.0), backend=:gmsh)
        @test_throws ArgumentError generate_mesh(geom; maxh=60.0, backend=:gmsh)
    end
end

@testset "generate_mesh: unknown backend (always runs, no Gmsh needed)" begin
    geom = load_step(STEP)
    @test_throws ArgumentError generate_mesh(geom; maxh=60.0, backend=:bogus)
end
