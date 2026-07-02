# DeloneWriteVTKExt: only exercised when WriteVTK is actually installed in
# this environment (the extension itself only needs the `WriteVTK` weakdep to
# be *defined* — see Project.toml [weakdeps]/[extensions] — precompiling and
# loading `Delone` never requires WriteVTK to be present). The main test suite
# must not gain a hard dependency on WriteVTK just to keep this file green, so
# everything below is guarded exactly like `test/makie_ext.jl`.
@testset "DeloneWriteVTKExt (real binary VTU export)" begin
    if Base.find_package("WriteVTK") === nothing
        @info "WriteVTK not installed; skipping DeloneWriteVTKExt verification " *
              "(export_vtu still exists as a stub that throws a clear error " *
              "pointing at export_vtk/WriteVTK without it)"
        @test_throws ArgumentError export_vtu(nothing, tempname())
    else
        @eval using WriteVTK

        @test Base.get_extension(Delone, :DeloneWriteVTKExt) !== nothing

        geom = load_step(STEP)
        s = mesh_session(geom; maxh=40.0)
        snap3 = level_snapshot(s, 1)
        @test snap3 isa MeshLevelSnapshot{3}

        outdir = mktempdir()

        # --- MeshLevelSnapshot path (volume + surface cells) --------------------
        path1 = joinpath(outdir, "frame_snapshot")
        out1 = export_vtu(snap3, path1)
        @test isfile(out1)
        @test filesize(out1) > 0

        txt1 = read(out1, String)
        @test startswith(strip(txt1), "<?xml")
        np1 = parse(Int, match(r"NumberOfPoints=\"(\d+)\"", txt1).captures[1])
        nc1 = parse(Int, match(r"NumberOfCells=\"(\d+)\"", txt1).captures[1])
        @test np1 == size(snap3.coordinates, 2)
        @test nc1 == size(snap3.volume_connectivity, 2) + size(snap3.surface_connectivity, 2)
        @test occursin("region", txt1)
        @test occursin("boundary_region", txt1)
        @test occursin("is_boundary", txt1)
        @test occursin("vtkZLibDataCompressor", txt1)  # real binary/compressed VTU, not ASCII

        # --- live mesh handle path (duck-typed fallback), volume-only -----------
        m_live = level_mesh(s, 1)
        path2 = joinpath(outdir, "frame_live")
        out2 = export_vtu(m_live, path2; include_surface=false)
        @test isfile(out2)
        txt2 = read(out2, String)
        nc2 = parse(Int, match(r"NumberOfCells=\"(\d+)\"", txt2).captures[1])
        @test nc2 == size(snap3.volume_connectivity, 2)

        # --- 2D snapshot path -----------------------------------------------------
        disk = Delone.Circle(0.0, 0.0, 1.0, "disk", "circle")
        geo2d = geometry2d(disk)
        s2 = mesh_session(geo2d; maxh=0.4)
        snap2 = level_snapshot(s2, 1)
        @test snap2 isa MeshLevelSnapshot{2}
        path3 = joinpath(outdir, "disk2d")
        out3 = export_vtu(snap2, path3)
        @test isfile(out3)
        txt3 = read(out3, String)
        np3 = parse(Int, match(r"NumberOfPoints=\"(\d+)\"", txt3).captures[1])
        nc3 = parse(Int, match(r"NumberOfCells=\"(\d+)\"", txt3).captures[1])
        @test np3 == size(snap2.coordinates, 2)
        @test nc3 == size(snap2.volume_connectivity, 2) + size(snap2.surface_connectivity, 2)
    end
end
