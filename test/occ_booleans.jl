@testset "OCC booleans: BRepAlgoAPI_* (1:1)" begin
    box    = Shape(BRepPrimAPI_MakeBox(gp_Pnt(0.0, 0.0, 0.0), gp_Pnt(1.0, 1.0, 1.0)))
    sphere = Shape(BRepPrimAPI_MakeSphere(gp_Pnt(0.0, 0.0, 0.0), 0.6))

    # Cut: box minus sphere
    cut = Shape(BRepAlgoAPI_Cut(box, sphere))
    @test !IsNull(cut)
    @test Netgen.GetNE(generate_mesh(OCCGeometry(cut); maxh=0.3)) > 0

    # Fuse
    b2 = Shape(BRepPrimAPI_MakeBox(gp_Pnt(0.5, 0.5, 0.5), gp_Pnt(1.5, 1.5, 1.5)))
    fused = Shape(BRepAlgoAPI_Fuse(box, b2))
    @test !IsNull(fused)

    # Common
    common = Shape(BRepAlgoAPI_Common(box, b2))
    @test !IsNull(common)
end
