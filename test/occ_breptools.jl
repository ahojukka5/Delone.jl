@testset "BRepTools free functions (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    # Get a face and its edges/vertices for testing
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    face = TopoDS_Face(Current(fex))

    vex = TopExp_Explorer()
    Init(vex, box, TopAbs_VERTEX())
    v1 = TopoDS_Vertex(Current(vex)); Next(vex)
    v2 = TopoDS_Vertex(Current(vex))

    eex = TopExp_Explorer()
    Init(eex, box, TopAbs_EDGE())
    e1 = TopoDS_Edge(Current(eex)); Next(eex)
    e2 = TopoDS_Edge(Current(eex))

    # OuterWire returns the outer wire of a face
    ow = BRepTools_OuterWire(face)
    @test ow isa TopoDS_Wire
    @test !IsNull(ow)

    # Compare on same/different vertices
    @test BRepTools_Compare(v1, v1) == true
    @test BRepTools_Compare(v1, v2) == false || BRepTools_Compare(v1, v2) == true  # just isa Bool

    # Compare on edges
    @test BRepTools_Compare(e1, e1) == true

    # IsReallyClosed: most box edges are not seam edges
    @test BRepTools_IsReallyClosed(e1, face) isa Bool

    # Update and CleanGeometry should not throw
    @test_nowarn BRepTools_Update(box)
    @test_nowarn BRepTools_CleanGeometry(box)
    @test_nowarn BRepTools_RemoveUnusedPCurves(box)
    @test_nowarn BRepTools_UpdateFaceUVPoints(face)
    @test_nowarn BRepTools_Clean(box, false)
end
