# DeloneMakieExt: only exercised when a Makie backend is actually installed in
# this environment (the extension itself only needs the `Makie` weakdep to be
# *defined* — see Project.toml [weakdeps]/[extensions] — but rendering needs a
# concrete backend). The main test suite must not gain a hard dependency on a
# Makie backend just to keep this file green, so everything below is guarded.
@testset "DeloneMakieExt (Makie plot recipes)" begin
    if Base.find_package("CairoMakie") === nothing
        @info "CairoMakie not installed; skipping DeloneMakieExt verification " *
              "(the extension itself still loads fine without a backend)"
        @test true   # keep the testset non-empty/non-vacuous under `--fail-fast`-style runners
    else
        @eval using CairoMakie

        @test Base.get_extension(Delone, :DeloneMakieExt) !== nothing

        geom = load_step(STEP)
        s = mesh_session(geom; maxh=40.0)
        snap3 = level_snapshot(s, 1)
        @test snap3 isa MeshLevelSnapshot{3}

        fap = Makie.plot(snap3)
        @test fap isa Makie.FigureAxisPlot
        @test fap.figure isa Makie.Figure

        m2 = Makie.mesh(snap3)
        @test m2 isa Makie.FigureAxisPlot

        hs = hierarchy_snapshot(s)
        @test hs isa MeshHierarchySnapshot
        fap_h = Makie.plot(hs)
        @test fap_h isa Makie.FigureAxisPlot

        # 2D snapshot path. `Circle` is disambiguated to `Delone.Circle`:
        # CairoMakie re-exports GeometryBasics' `Circle`, which otherwise
        # collides with Delone's 2D CSG primitive of the same name.
        disk = Delone.Circle(0.0, 0.0, 1.0, "disk", "circle")
        geo2d = geometry2d(disk)
        s2 = mesh_session(geo2d; maxh=0.4)
        snap2 = level_snapshot(s2, 1)
        @test snap2 isa MeshLevelSnapshot{2}
        fap2 = Makie.plot(snap2)
        @test fap2 isa Makie.FigureAxisPlot
    end
end
