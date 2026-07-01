@testset "Segment (1:1)" begin
    s = Segment()
    @test Netgen.GetNP(s) == 2
    Netgen.SetIndex(s, 7)
    @test Netgen.GetIndex(s) == 7
end

@testset "FaceDescriptor (1:1)" begin
    fd = FaceDescriptor()
    Netgen.SetDomainIn(fd, 1)
    Netgen.SetDomainOut(fd, 0)
    Netgen.SetBCProperty(fd, 3)
    @test Netgen.DomainIn(fd) == 1
    @test Netgen.DomainOut(fd) == 0
    @test Netgen.BCProperty(fd) == 3
    Netgen.SetBCName(fd, "wall")
    @test Netgen.GetBCName(fd) == "wall"
end

@testset "LocalH (new_localh + SetH/GetH)" begin
    pmin = Netgen.Point3d(0.0, 0.0, 0.0)
    pmax = Netgen.Point3d(1.0, 1.0, 1.0)
    lh = new_localh(pmin, pmax, 0.3)
    p = Netgen.Point3d(0.5, 0.5, 0.5)
    Netgen.SetH(lh, p, 0.1)
    @test Netgen.GetH(lh, p) <= 0.1 + 1e-10
    hmin = Netgen.GetMinH(lh, pmin, pmax)
    @test hmin > 0.0
end

@testset "MeshTopology connectivity (GetEdgeVertices / GetFaceVertices / GetFaceEdges)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    Netgen.UpdateTopology(m)
    t = Netgen.GetTopology(m)
    ne = Netgen.GetNEdges(t)
    @test ne > 0

    buf2 = zeros(Int32, 2)
    Netgen.GetEdgeVertices(t, 1, buf2)
    @test buf2[1] >= 1 && buf2[2] >= 1
    @test buf2[1] != buf2[2]

    nf = Netgen.GetNFaces(t)
    @test nf > 0
    buf4 = zeros(Int32, 4)
    n = Netgen.GetFaceVertices(t, 1, buf4)
    @test n >= 3
    @test all(buf4[1:n] .>= 1)

    buf3 = zeros(Int32, 4)
    ne_face = Netgen.GetFaceEdges(t, 1, buf3)
    @test ne_face >= 3
end

@testset "Additional Mesh methods (AddPoint / CheckVolumeMesh)" begin
    m = Netgen.new_mesh()
    p = Netgen.Point3d(0.0, 0.0, 0.0)
    idx = Netgen.AddPoint(m, p)
    @test Netgen.GetNP(m) >= 1

    geom = load_step(STEP)
    m2 = generate_mesh(geom; maxh=40.0)
    @test Netgen.CheckVolumeMesh(m2) == 0
    @test Netgen.CheckConsistentBoundary(m2) == 0
end
