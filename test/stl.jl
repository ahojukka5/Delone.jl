const STL_TET = joinpath(@__DIR__, "fixtures", "tet.stl")

@testset "I.STLParameters (1:1 fields)" begin
    p = I.STLParameters()
    v0 = I.yangle(p)
    @test v0 > 0.0
    I.yangle!(p, 30.0)
    @test I.yangle(p) ≈ 30.0
    I.contyangle!(p, 20.0)
    @test I.contyangle(p) ≈ 20.0
end

@testset "I.STLGeometry (I.LoadSTL / GetNT / GetNP)" begin
    stl = load_stl(STL_TET)
    @test I.GetNT(stl) == 4
    @test I.GetNP(stl) == 4
end

@testset "STL -> volume mesh, end-to-end via the public API" begin
    geom = load_stl(STL_TET)
    m = generate_mesh(geom; maxh=10.0)
    @test num_nodes(m) > 0
    @test num_cells(m) > 0
    @test mesh_dimension(m) == 3

    res = generate_mesh_result(geom, mesh_options(maxh=10.0))
    @test res.success
    @test mesh(res) isa typeof(m)
end
