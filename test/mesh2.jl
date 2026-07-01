@testset "EdgeDescriptor (1:1)" begin
    ed = EdgeDescriptor()
    Netgen.SetEdgeNr(ed, 3)
    @test Netgen.EdgeNr(ed) == 3
    Netgen.SetSurfNr(ed, 0, 1)
    Netgen.SetSurfNr(ed, 1, 2)
    @test Netgen.SurfNr(ed, 0) == 1
    @test Netgen.SurfNr(ed, 1) == 2
    Netgen.SetName(ed, "boundary1")
    @test Netgen.GetName(ed) == "boundary1"
    Netgen.SetSingEdgeLeft(ed, 0.5)
    @test Netgen.SingEdgeLeft(ed) ≈ 0.5
    Netgen.SetSingEdgeRight(ed, 0.25)
    @test Netgen.SingEdgeRight(ed) ≈ 0.25
end

@testset "Mesh GetBox" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    b = Netgen.GetBox(m)
    @test b isa Box3d
    @test Netgen.MaxX(b) > Netgen.MinX(b)
    @test Netgen.MaxY(b) > Netgen.MinY(b)
    @test Netgen.MaxZ(b) > Netgen.MinZ(b)
end

@testset "Mesh GetH / SetGlobalH / SetMinimalH" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    h = Netgen.GetH(m, Netgen.Point3d(0.0, 0.0, 0.0))
    @test h > 0.0
    Netgen.SetGlobalH(m, 20.0)
    Netgen.SetMinimalH(m, 1.0)
end

@testset "Mesh CalcMinMaxAngle" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    Netgen.CalcMinMaxAngle(m, 0.1)   # void — runs quality check as side-effect
end

@testset "Mesh GetSurfaceElementsOfFace" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nse_total = Netgen.GetNSE(m)
    @test nse_total > 0
    buf = zeros(Int32, nse_total)
    n = Netgen.GetSurfaceElementsOfFace(m, 1, buf)
    @test n > 0
    @test all(buf[1:n] .>= 0)   # SurfaceElementIndex is 0-based
end

@testset "Mesh PureTetMesh / PureTrigMesh" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test Netgen.PureTetMesh(m)
    @test Netgen.PureTrigMesh(m, 1)
end

@testset "Mesh SetDimension / SurfaceMeshOrientation" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    Netgen.SetDimension(m, 3)
    Netgen.SurfaceMeshOrientation(m)
end
