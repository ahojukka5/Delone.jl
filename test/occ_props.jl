@testset "GProp_GProps + BRepGProp (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 2.0, 3.0))

    g = GProp_GProps()
    BRepGProp_VolumeProperties(box, g)
    @test Mass(g) ≈ 6.0 atol=1e-10          # 1*2*3 = 6

    g2 = GProp_GProps()
    BRepGProp_SurfaceProperties(box, g2)
    @test Mass(g2) ≈ 2*(1*2 + 2*3 + 1*3) atol=1e-10   # 2*(2+6+3) = 22

    c = CentreOfMass(g)
    @test X(c) ≈ 0.5 atol=1e-10
    @test Y(c) ≈ 1.0 atol=1e-10
    @test Z(c) ≈ 1.5 atol=1e-10
end

@testset "Bnd_Box + BRepBndLib_Add (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(gp_Pnt(1.0, 2.0, 3.0), gp_Pnt(4.0, 5.0, 6.0)))
    b = Bnd_Box()
    @test IsVoid(b)
    BRepBndLib_Add(box, b)
    @test !IsVoid(b)
    # BRepBndLib::Add inflates bounds by the shape tolerance (~1e-7); use atol=1e-5
    @test CornerMin_X(b) ≈ 1.0 atol=1e-5
    @test CornerMin_Y(b) ≈ 2.0 atol=1e-5
    @test CornerMin_Z(b) ≈ 3.0 atol=1e-5
    @test CornerMax_X(b) ≈ 4.0 atol=1e-5
    @test CornerMax_Y(b) ≈ 5.0 atol=1e-5
    @test CornerMax_Z(b) ≈ 6.0 atol=1e-5
    @test !IsOut(b, gp_Pnt(2.0, 3.0, 4.0))
    @test  IsOut(b, gp_Pnt(10.0, 10.0, 10.0))
end

@testset "BRep_Tool_Pnt (1:1)" begin
    v = Vertex(BRepBuilderAPI_MakeVertex(gp_Pnt(3.0, 4.0, 5.0)))
    p = BRep_Tool_Pnt(v)
    @test X(p) ≈ 3.0 atol=1e-12
    @test Y(p) ≈ 4.0 atol=1e-12
    @test Z(p) ≈ 5.0 atol=1e-12
end
