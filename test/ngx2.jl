@testset "Ngx_Mesh GetPoint" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nm = Netgen.Ngx_Mesh(m)
    np = Netgen.GetNP(m)
    @test np > 0
    p = Netgen.GetPoint(nm, 0)   # 0-based indexing
    @test Netgen.X(p) isa Float64
    @test Netgen.Y(p) isa Float64
    @test Netgen.Z(p) isa Float64
end

@testset "Ngx_Mesh GetNIdentifications" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nm = Netgen.Ngx_Mesh(m)
    @test Netgen.GetNIdentifications(nm) >= 0
end

@testset "Ngx_Mesh element-face connectivity (requires UpdateTopology)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    Netgen.UpdateTopology(m)
    nm = Netgen.Ngx_Mesh(m)
    ne = Netgen.GetNE(m)
    @test ne > 0
    buf = zeros(Int32, 6)
    n = Netgen.GetElement_Faces(nm, 0, buf)
    @test n == 4        # tet has 4 faces
    @test all(buf[1:n] .>= 0)
end

@testset "Ngx_Mesh GetSurfaceElement_Face" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    Netgen.UpdateTopology(m)
    nm = Netgen.Ngx_Mesh(m)
    nse = Netgen.GetNSE(m)
    @test nse > 0
    fi = Netgen.GetSurfaceElement_Face(nm, 0)
    @test fi >= 0
end

@testset "OptimizeVolume (free function)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    mp = Netgen.MeshingParameters()
    Netgen.maxh!(mp, 40.0)
    result = OptimizeVolume(mp, m)
    @test result == MESHING3_OK
end
