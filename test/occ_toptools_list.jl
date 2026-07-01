@testset "TopTools_ListOfShape (1:1)" begin
    l = TopTools_ListOfShape()
    @test l isa TopTools_ListOfShape
    @test IsEmpty(l) == true
    @test Extent(l) == 0

    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    f1 = TopoDS_Face(Current(fex)); Next(fex)
    f2 = TopoDS_Face(Current(fex))

    Append(l, f1)
    Append(l, f2)
    @test Extent(l) == 2
    @test IsEmpty(l) == false

    @test First(l) isa TopoDS_Shape
    @test Last(l) isa TopoDS_Shape

    Clear(l)
    @test IsEmpty(l) == true
    @test Extent(l) == 0
end
