const STL_TET = joinpath(@__DIR__, "fixtures", "tet.stl")

@testset "STLParameters (1:1 fields)" begin
    p = STLParameters()
    v0 = Netgen.yangle(p)
    @test v0 > 0.0
    Netgen.yangle!(p, 30.0)
    @test Netgen.yangle(p) ≈ 30.0
    Netgen.contyangle!(p, 20.0)
    @test Netgen.contyangle(p) ≈ 20.0
end

@testset "STLGeometry (LoadSTL / GetNT / GetNP)" begin
    stl = load_stl(STL_TET)
    @test Netgen.GetNT(stl) == 4
    @test Netgen.GetNP(stl) == 4
end
