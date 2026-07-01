@testset "TopTools_IndexedMapOfShape + TopExp_MapShapes (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    # Integer constants
    @test TopAbs_FACE()   == 4
    @test TopAbs_EDGE()   == 6
    @test TopAbs_VERTEX() == 7
    @test TopAbs_SOLID()  == 2

    # Map faces
    fmap = TopTools_IndexedMapOfShape()
    TopExp_MapShapes(box, TopAbs_FACE(), fmap)
    @test Extent(fmap) == 6

    face1 = FindKey(fmap, 1)
    @test !IsNull(face1)
    @test FindIndex(fmap, face1) == 1
    @test Contains(fmap, face1)

    # Map edges
    emap = TopTools_IndexedMapOfShape()
    TopExp_MapShapes(box, TopAbs_EDGE(), emap)
    @test Extent(emap) == 12

    # Map vertices
    vmap = TopTools_IndexedMapOfShape()
    TopExp_MapShapes(box, TopAbs_VERTEX(), vmap)
    @test Extent(vmap) == 8

    # Clear
    Clear(vmap)
    @test Extent(vmap) == 0
end
