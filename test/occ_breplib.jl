@testset "BRepLib repair/regularization free functions (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    eex = TopExp_Explorer()
    Init(eex, box, TopAbs_EDGE())
    edge = TopoDS_Edge(Current(eex))

    @test BRepLib_CheckSameRange(edge, 1.0e-12) isa Bool
    @test_nowarn BRepLib_SameRange(edge, 1.0e-5)
    @test BRepLib_BuildCurve3d(edge, 1.0e-5, GeomAbs_C1(), 14, 0) isa Bool
    @test BRepLib_BuildCurves3d(box, 1.0e-5, GeomAbs_C1(), 14, 0) isa Bool
    @test BRepLib_BuildCurves3d(box) isa Bool
    @test_nowarn BRepLib_SameParameter(edge, 1.0e-5)
    @test_nowarn BRepLib_SameParameter(box, 1.0e-5, false)

    solid = Solid(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    @test BRepLib_OrientClosedSolid(solid) isa Bool

    @test_nowarn BRepLib_EncodeRegularity(box, 1.0e-10)

    edges = TopTools_ListOfShape()
    Append(edges, edge)
    @test_nowarn BRepLib_EncodeRegularity(box, edges, 1.0e-10)

    @test GeomAbs_C0() isa Integer
    @test GeomAbs_G1() isa Integer
    @test GeomAbs_C1() isa Integer
    @test GeomAbs_G2() isa Integer
    @test GeomAbs_C2() isa Integer
    @test GeomAbs_C3() isa Integer
    @test GeomAbs_CN() isa Integer
end
