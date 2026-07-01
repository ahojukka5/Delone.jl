@testset "OCC load + GenerateMesh + counts (1:1 names)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test Netgen.GetDimension(m) == 3
    @test Netgen.GetNP(m) > 0
    @test Netgen.GetNE(m) > 0
    @test Netgen.GetNSE(m) > 0
end

@testset "extraction (Julia loops over 1:1 accessors)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    P = points(m)
    @test size(P) == (3, Netgen.GetNP(m))
    T = tetrahedra(m)
    @test size(T) == (4, Netgen.GetNE(m))
    @test all(1 .<= T .<= Netgen.GetNP(m))
    S = surface_triangles(m)
    @test size(S) == (3, Netgen.GetNSE(m))
    # element type via the 1:1 GetType
    @test Netgen.GetType(Netgen.VolumeElement(m, 1)) == NG_TET
    @test Netgen.GetType(Netgen.SurfaceElement(m, 1)) == NG_TRIG
end

@testset "topology (1:1 UpdateTopology / GetTopology / GetNEdges / GetNFaces)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    Netgen.UpdateTopology(m)
    t = Netgen.GetTopology(m)
    @test Netgen.GetNEdges(t) > 0
    @test Netgen.GetNFaces(t) > 0
end

@testset "Save / Load (1:1)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    tmp = tempname() * ".vol"
    Netgen.Save(m, tmp)
    @test isfile(tmp)
    m2 = Netgen.new_mesh()
    Netgen.Load(m2, tmp)
    @test Netgen.GetNP(m2) == Netgen.GetNP(m)
    rm(tmp; force=true)
end
