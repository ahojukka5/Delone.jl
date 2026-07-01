@testset "BRepFilletAPI_MakeFillet (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    # Collect one edge via TopTools_IndexedMapOfShape
    emap = TopTools_IndexedMapOfShape()
    TopExp_MapShapes(box, TopAbs_EDGE(), emap)
    @test Extent(emap) == 12   # a box has 12 edges

    edge = TopoDS_Edge(FindKey(emap, 1))

    fillet = BRepFilletAPI_MakeFillet(box)
    Add(fillet, 0.1, edge)
    Build(fillet)
    @test IsDone(fillet)
    result = Shape(fillet)
    @test !IsNull(result)
    @test NbContours(fillet) >= 1
end

@testset "BRepFilletAPI_MakeChamfer (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    emap = TopTools_IndexedMapOfShape()
    TopExp_MapShapes(box, TopAbs_EDGE(), emap)
    edge = TopoDS_Edge(FindKey(emap, 1))

    chamfer = BRepFilletAPI_MakeChamfer(box)
    Add(chamfer, 0.1, edge)
    Build(chamfer)
    @test IsDone(chamfer)
    result = Shape(chamfer)
    @test !IsNull(result)
end
